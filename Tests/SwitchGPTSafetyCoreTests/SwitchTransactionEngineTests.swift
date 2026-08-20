import Darwin
import Foundation
import XCTest

@testable import SwitchGPTSafetyCore

final class SwitchTransactionEngineTests: XCTestCase {
  private let accountA = IdentityID(rawValue: "account-a")!
  private let accountB = IdentityID(rawValue: "account-b")!
  private let unexpectedAccount = IdentityID(rawValue: "unexpected-account")!
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for directory in temporaryDirectories {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
  }

  func testSuccessfulSwitchUsesOneTargetLaunchAndNoRollbackLaunch() throws {
    let harness = try makeHarness()
    let result = try harness.engine.beginSwitch(from: accountA, to: accountB)
    let desktop = try harness.desktop.snapshot()

    XCTAssertEqual(result.phase, .committed)
    XCTAssertEqual(result.targetLaunchAttempts, 1)
    XCTAssertEqual(result.rollbackLaunchAttempts, 0)
    XCTAssertEqual(desktop.installedIdentity, accountB)
    XCTAssertTrue(desktop.isRunning)
    XCTAssertEqual(desktop.startsByIdentity[accountB.rawValue], 1)
    XCTAssertNil(desktop.startsByIdentity[accountA.rawValue])
  }

  func testTargetVerificationFailureRollsBackExactlyOnce() throws {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let engine = SwitchTransactionEngine(store: store, desktop: desktop) {
      [unexpectedAccount] point in
      if point == .afterTargetStarted {
        try desktop.install(identity: unexpectedAccount)
      }
    }

    let result = try engine.beginSwitch(from: accountA, to: accountB)
    let state = try desktop.snapshot()

    XCTAssertEqual(result.phase, .rolledBack)
    XCTAssertEqual(result.failureReason, .targetIdentityMismatch)
    XCTAssertEqual(result.targetLaunchAttempts, 1)
    XCTAssertEqual(result.rollbackLaunchAttempts, 1)
    XCTAssertEqual(state.installedIdentity, accountA)
    XCTAssertEqual(state.startsByIdentity[accountB.rawValue], 1)
    XCTAssertEqual(state.startsByIdentity[accountA.rawValue], 1)
  }

  func testProcessRestartAfterPreparedRecoversOnlyAndNeverInstallsTarget() throws {
    let harness = try makeHarness(crashAt: .afterPrepared)
    XCTAssertThrowsError(try harness.engine.beginSwitch(from: accountA, to: accountB)) { error in
      XCTAssertEqual(error as? SimulatedProcessExit, SimulatedProcessExit(at: .afterPrepared))
    }

    let recovered = try makeRecoveryEngine(root: harness.root).recover()
    let state = try harness.desktop.snapshot()

    XCTAssertEqual(recovered.mode, .recoveryOnly)
    XCTAssertEqual(recovered.phase, .rolledBack)
    XCTAssertEqual(recovered.targetLaunchAttempts, 0)
    XCTAssertEqual(recovered.rollbackLaunchAttempts, 1)
    XCTAssertNil(state.startsByIdentity[accountB.rawValue])
    XCTAssertEqual(state.startsByIdentity[accountA.rawValue], 1)
  }

  func testFailedStopDoesNotMisclassifyPendingTerminationAsSafeRollback() throws {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let fixture = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let desktop = StopFailingDesktop(base: fixture)
    let engine = SwitchTransactionEngine(store: store, desktop: desktop)

    let result = try engine.beginSwitch(from: accountA, to: accountB)
    let state = try fixture.snapshot()

    XCTAssertEqual(result.phase, .manualRecoveryRequired)
    XCTAssertEqual(result.rollbackLaunchAttempts, 0)
    XCTAssertTrue(state.isRunning)
    XCTAssertEqual(state.installedIdentity, accountA)
    XCTAssertTrue(state.startsByIdentity.isEmpty)
  }

  func testProcessRestartAfterTargetStartedRecoversSourceWithoutSecondTargetLaunch() throws {
    let harness = try makeHarness(crashAt: .afterTargetStarted)
    XCTAssertThrowsError(try harness.engine.beginSwitch(from: accountA, to: accountB))

    let recovered = try makeRecoveryEngine(root: harness.root).recover()
    let state = try harness.desktop.snapshot()

    XCTAssertEqual(recovered.phase, .rolledBack)
    XCTAssertEqual(recovered.targetLaunchAttempts, 1)
    XCTAssertEqual(recovered.rollbackLaunchAttempts, 1)
    XCTAssertEqual(state.startsByIdentity[accountB.rawValue], 1)
    XCTAssertEqual(state.startsByIdentity[accountA.rawValue], 1)
    XCTAssertEqual(state.installedIdentity, accountA)
  }

  func testProcessRestartAfterTargetInstalledNeverLaunchesTarget() throws {
    let harness = try makeHarness(crashAt: .afterTargetInstalled)
    XCTAssertThrowsError(try harness.engine.beginSwitch(from: accountA, to: accountB))

    let recovered = try makeRecoveryEngine(root: harness.root).recover()
    let state = try harness.desktop.snapshot()

    XCTAssertEqual(recovered.phase, .rolledBack)
    XCTAssertEqual(recovered.targetLaunchAttempts, 0)
    XCTAssertEqual(recovered.rollbackLaunchAttempts, 1)
    XCTAssertNil(state.startsByIdentity[accountB.rawValue])
    XCTAssertEqual(state.startsByIdentity[accountA.rawValue], 1)
  }

  func testProcessRestartAfterTargetLaunchReservationDoesNotRetryTarget() throws {
    let harness = try makeHarness(crashAt: .afterTargetLaunchReserved)
    XCTAssertThrowsError(try harness.engine.beginSwitch(from: accountA, to: accountB))

    let recovered = try makeRecoveryEngine(root: harness.root).recover()
    let state = try harness.desktop.snapshot()

    XCTAssertEqual(recovered.phase, .rolledBack)
    XCTAssertEqual(recovered.targetLaunchAttempts, 1)
    XCTAssertEqual(recovered.rollbackLaunchAttempts, 1)
    XCTAssertNil(state.startsByIdentity[accountB.rawValue])
    XCTAssertEqual(state.startsByIdentity[accountA.rawValue], 1)
  }

  func testCrashAfterRollbackLaunchReservationRequiresManualRecoveryWithoutLoop() throws {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let engine = SwitchTransactionEngine(store: store, desktop: desktop) { [accountA] point in
      if point == .afterTargetStarted {
        try desktop.install(identity: accountA)
      }
      if point == .afterRollbackLaunchReserved {
        throw SimulatedProcessExit(at: point)
      }
    }
    XCTAssertThrowsError(try engine.beginSwitch(from: accountA, to: accountB))

    let recovered = try makeRecoveryEngine(root: root).recover()
    let state = try desktop.snapshot()

    XCTAssertEqual(recovered.phase, .manualRecoveryRequired)
    XCTAssertEqual(recovered.failureReason, .recoveryLaunchBudgetExhausted)
    XCTAssertEqual(recovered.rollbackLaunchAttempts, 1)
    XCTAssertFalse(state.isRunning)
    XCTAssertNil(state.startsByIdentity[accountA.rawValue])
  }

  func testCrashAfterRollbackStartedVerifiesExistingSourceWithoutSecondRollbackLaunch() throws {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let engine = SwitchTransactionEngine(store: store, desktop: desktop) { [accountA] point in
      if point == .afterTargetStarted {
        try desktop.install(identity: accountA)
      }
      if point == .afterRollbackStarted {
        throw SimulatedProcessExit(at: point)
      }
    }
    XCTAssertThrowsError(try engine.beginSwitch(from: accountA, to: accountB))

    let recovered = try makeRecoveryEngine(root: root).recover()
    let state = try desktop.snapshot()

    XCTAssertEqual(recovered.phase, .rolledBack)
    XCTAssertEqual(recovered.rollbackLaunchAttempts, 1)
    XCTAssertEqual(state.startsByIdentity[accountA.rawValue], 1)
    XCTAssertTrue(state.isRunning)
  }

  func testTerminalRecoveryIsIdempotent() throws {
    let harness = try makeHarness(crashAt: .afterTargetStarted)
    XCTAssertThrowsError(try harness.engine.beginSwitch(from: accountA, to: accountB))

    let first = try makeRecoveryEngine(root: harness.root).recover()
    let before = try harness.desktop.snapshot()
    let second = try makeRecoveryEngine(root: harness.root).recover()
    let after = try harness.desktop.snapshot()

    XCTAssertEqual(first.id, second.id)
    XCTAssertEqual(first.mode, second.mode)
    XCTAssertEqual(first.phase, second.phase)
    XCTAssertEqual(first.targetLaunchAttempts, second.targetLaunchAttempts)
    XCTAssertEqual(first.rollbackLaunchAttempts, second.rollbackLaunchAttempts)
    XCTAssertEqual(first.failureReason, second.failureReason)
    XCTAssertEqual(before.startsByIdentity, after.startsByIdentity)
    XCTAssertEqual(before.stopCount, after.stopCount)
  }

  func testGlobalLockRejectsConcurrentTransaction() throws {
    let harness = try makeHarness()
    let heldLock = try TransactionLock(url: harness.store.lockURL)
    defer { heldLock.release() }

    XCTAssertThrowsError(try harness.engine.beginSwitch(from: accountA, to: accountB)) { error in
      XCTAssertEqual(error as? SafetyError, .lockUnavailable)
    }
  }

  func testCompletedTransactionDirectoryCannotBeReused() throws {
    let harness = try makeHarness()
    XCTAssertEqual(
      try harness.engine.beginSwitch(from: accountA, to: accountB).phase,
      .committed
    )

    XCTAssertThrowsError(try harness.engine.beginSwitch(from: accountB, to: accountA)) { error in
      XCTAssertEqual(error as? SafetyError, .existingTransaction)
    }
    XCTAssertEqual(try harness.desktop.snapshot().startsByIdentity[accountB.rawValue], 1)
  }

  func testPersistedStateUsesRestrictedPermissions() throws {
    let harness = try makeHarness(crashAt: .afterPrepared)
    XCTAssertThrowsError(try harness.engine.beginSwitch(from: accountA, to: accountB))

    let directoryMode = try mode(of: harness.store.directoryURL)
    let stateMode = try mode(of: harness.store.stateURL)
    let lockMode = try mode(of: harness.store.lockURL)
    XCTAssertEqual(directoryMode, 0o700)
    XCTAssertEqual(stateMode, 0o600)
    XCTAssertEqual(lockMode, 0o600)
  }

  func testStoreRejectsLaunchBudgetAboveOne() throws {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    var record = TransactionRecord(sourceIdentity: accountA, targetIdentity: accountB)
    record.targetLaunchAttempts = 2

    XCTAssertThrowsError(try store.save(record)) { error in
      XCTAssertEqual(error as? SafetyError, .invalidPersistedState)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))
  }

  func testIdentityDecoderRejectsEmptyValue() throws {
    let data = Data("\"   \"".utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(IdentityID.self, from: data))
  }

  private func makeHarness(crashAt checkpoint: SafetyCheckpoint? = nil) throws -> Harness {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let engine = SwitchTransactionEngine(store: store, desktop: desktop) { point in
      if point == checkpoint {
        throw SimulatedProcessExit(at: point)
      }
    }
    return Harness(root: root, store: store, desktop: desktop, engine: engine)
  }

  private func makeRecoveryEngine(root: URL) throws -> SwitchTransactionEngine {
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(directoryURL: root.appendingPathComponent("desktop"))
    return SwitchTransactionEngine(store: store, desktop: desktop)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }

  private func mode(of url: URL) throws -> mode_t {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return mode_t((attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0)
  }
}

private final class StopFailingDesktop: TransactionDesktop {
  private let base: FixtureDesktop

  init(base: FixtureDesktop) {
    self.base = base
  }

  func isRunning() throws -> Bool { try base.isRunning() }
  func currentIdentity() throws -> IdentityID { try base.currentIdentity() }
  func stop() throws { throw POSIXError(.ETIMEDOUT) }
  func install(identity: IdentityID) throws { try base.install(identity: identity) }
  func start() throws { try base.start() }
}

private struct Harness {
  let root: URL
  let store: TransactionStore
  let desktop: FixtureDesktop
  let engine: SwitchTransactionEngine
}
