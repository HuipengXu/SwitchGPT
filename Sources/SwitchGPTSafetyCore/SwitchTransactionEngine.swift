import Foundation

public protocol TransactionDesktop: AnyObject {
  func isRunning() throws -> Bool
  func currentIdentity() throws -> IdentityID
  func stop() throws
  func install(identity: IdentityID) throws
  func start() throws
}

public final class SwitchTransactionEngine {
  public typealias CheckpointHandler = (SafetyCheckpoint) throws -> Void

  private let store: TransactionStore
  private let desktop: TransactionDesktop
  private let checkpointHandler: CheckpointHandler

  public init(
    store: TransactionStore,
    desktop: TransactionDesktop,
    checkpointHandler: @escaping CheckpointHandler = { _ in }
  ) {
    self.store = store
    self.desktop = desktop
    self.checkpointHandler = checkpointHandler
  }

  @discardableResult
  public func beginSwitch(from source: IdentityID, to target: IdentityID) throws
    -> TransactionRecord
  {
    guard source != target else { throw SafetyError.sourceAndTargetMatch }
    let lock = try TransactionLock(url: store.lockURL)
    defer { lock.release() }

    guard try store.load() == nil else { throw SafetyError.existingTransaction }
    guard try desktop.currentIdentity() == source else {
      throw SafetyError.sourceIdentityMismatch
    }

    var record = TransactionRecord(sourceIdentity: source, targetIdentity: target)
    try store.save(record)
    try checkpoint(.afterPrepared)

    do {
      record.phase = .stoppingForTarget
      try store.save(record)
      if try desktop.isRunning() {
        try desktop.stop()
      }
      try checkpoint(.afterTargetStopped)

      record.phase = .installingTarget
      try store.save(record)
      try desktop.install(identity: target)
      record.targetWasInstalled = true
      try store.save(record)
      try checkpoint(.afterTargetInstalled)

      record.phase = .startingTarget
      guard record.targetLaunchAttempts == 0 else {
        record.failureReason = .targetOperationFailed
        return try rollback(record)
      }
      record.targetLaunchAttempts = 1
      try store.save(record)
      try checkpoint(.afterTargetLaunchReserved)
      try desktop.start()
      try checkpoint(.afterTargetStarted)

      record.phase = .verifyingTarget
      try store.save(record)
      guard try desktop.currentIdentity() == target else {
        record.failureReason = .targetIdentityMismatch
        return try rollback(record)
      }

      record.phase = .committed
      try store.save(record)
      return record
    } catch let processExit as SimulatedProcessExit {
      throw processExit
    } catch {
      record.failureReason = .targetOperationFailed
      return try rollback(record)
    }
  }

  @discardableResult
  public func recover(lockBehavior: RecoveryLockBehavior = .failIfBusy) throws -> TransactionRecord
  {
    try recoverWithDisposition(lockBehavior: lockBehavior).record
  }

  public func recoverWithDisposition(
    lockBehavior: RecoveryLockBehavior = .failIfBusy
  ) throws -> RecoveryResult {
    let lock = try TransactionLock(
      url: store.lockURL,
      waitUntilAvailable: lockBehavior == .waitForActiveTransaction
    )
    defer { lock.release() }

    guard var record = try store.load() else { throw SafetyError.missingTransaction }
    guard !record.phase.isTerminal else {
      return RecoveryResult(record: record, disposition: .observedTerminal)
    }

    record.mode = .recoveryOnly
    record.failureReason = record.failureReason ?? .interrupted
    try store.save(record)
    return RecoveryResult(
      record: try rollback(record),
      disposition: .performedRecovery
    )
  }

  private func rollback(_ input: TransactionRecord) throws -> TransactionRecord {
    var record = input
    record.mode = .recoveryOnly

    if record.rollbackLaunchAttempts >= 1 {
      do {
        if try desktop.isRunning(), try desktop.currentIdentity() == record.recoveryIdentity {
          record.phase = .rolledBack
        } else {
          record.phase = .manualRecoveryRequired
          record.failureReason = .recoveryLaunchBudgetExhausted
        }
      } catch {
        record.phase = .manualRecoveryRequired
        record.failureReason = .recoveryOperationFailed
      }
      try store.save(record)
      return record
    }

    do {
      record.phase = .rollbackStopping
      try store.save(record)
      if try desktop.isRunning() {
        try desktop.stop()
      }
      try checkpoint(.afterRollbackStopped)

      record.phase = .rollbackRestoring
      try store.save(record)
      try desktop.install(identity: record.recoveryIdentity)
      record.targetWasInstalled = false
      try store.save(record)
      try checkpoint(.afterSourceRestored)

      record.phase = .rollbackStarting
      record.rollbackLaunchAttempts = 1
      try store.save(record)
      try checkpoint(.afterRollbackLaunchReserved)
      try desktop.start()
      try checkpoint(.afterRollbackStarted)

      record.phase = .rollbackVerifying
      try store.save(record)
      guard try desktop.currentIdentity() == record.recoveryIdentity else {
        record.phase = .manualRecoveryRequired
        record.failureReason = .recoveryOperationFailed
        try store.save(record)
        return record
      }

      record.phase = .rolledBack
      try store.save(record)
      return record
    } catch let processExit as SimulatedProcessExit {
      throw processExit
    } catch {
      record.phase = .manualRecoveryRequired
      record.failureReason = .recoveryOperationFailed
      try store.save(record)
      return record
    }
  }

  private func checkpoint(_ point: SafetyCheckpoint) throws {
    try checkpointHandler(point)
  }
}
