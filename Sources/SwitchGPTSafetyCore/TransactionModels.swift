import Foundation

public struct IdentityID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(rawValue: String) {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    self.rawValue = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let identity = Self(rawValue: value) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "IdentityID must not be empty"
      )
    }
    self = identity
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public enum TransactionMode: String, Codable, Sendable {
  case switching
  case recoveryOnly
}

public enum TransactionPhase: String, Codable, Sendable {
  case prepared
  case stoppingForTarget
  case installingTarget
  case startingTarget
  case verifyingTarget
  case committed
  case rollbackStopping
  case rollbackRestoring
  case rollbackStarting
  case rollbackVerifying
  case rolledBack
  case manualRecoveryRequired

  public var isTerminal: Bool {
    switch self {
    case .committed, .rolledBack, .manualRecoveryRequired:
      true
    default:
      false
    }
  }
}

public enum FailureReason: String, Codable, Sendable {
  case targetOperationFailed
  case targetIdentityMismatch
  case interrupted
  case recoveryOperationFailed
  case recoveryLaunchBudgetExhausted
}

public enum RecoveryLockBehavior: Sendable {
  case failIfBusy
  case waitForActiveTransaction
}

public enum RecoveryDisposition: Sendable {
  case performedRecovery
  case observedTerminal
}

public struct RecoveryResult: Sendable {
  public let record: TransactionRecord
  public let disposition: RecoveryDisposition

  public init(record: TransactionRecord, disposition: RecoveryDisposition) {
    self.record = record
    self.disposition = disposition
  }
}

public struct TransactionRecord: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let id: UUID
  public let sourceIdentity: IdentityID
  public let targetIdentity: IdentityID
  public let recoveryIdentity: IdentityID
  public var mode: TransactionMode
  public var phase: TransactionPhase {
    didSet { updatedAt = Date() }
  }
  public var targetLaunchAttempts: Int
  public var rollbackLaunchAttempts: Int
  public var targetWasInstalled: Bool
  public var failureReason: FailureReason?
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    sourceIdentity: IdentityID,
    targetIdentity: IdentityID,
    now: Date = Date()
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.id = id
    self.sourceIdentity = sourceIdentity
    self.targetIdentity = targetIdentity
    recoveryIdentity = sourceIdentity
    mode = .switching
    phase = .prepared
    targetLaunchAttempts = 0
    rollbackLaunchAttempts = 0
    targetWasInstalled = false
    failureReason = nil
    createdAt = now
    updatedAt = now
  }
}

public enum SafetyCheckpoint: String, Sendable {
  case afterPrepared
  case afterTargetStopped
  case afterTargetInstalled
  case afterTargetLaunchReserved
  case afterTargetStarted
  case afterRollbackStopped
  case afterSourceRestored
  case afterRollbackLaunchReserved
  case afterRollbackStarted
}

public struct SimulatedProcessExit: Error, Equatable, Sendable {
  public let checkpoint: SafetyCheckpoint

  public init(at checkpoint: SafetyCheckpoint) {
    self.checkpoint = checkpoint
  }
}

public enum SafetyError: Error, Equatable, Sendable {
  case sourceAndTargetMatch
  case sourceIdentityMismatch
  case existingTransaction
  case missingTransaction
  case lockUnavailable
  case unsafeStorage
  case corruptedPersistedState
  case unsupportedEnvelopeSchemaVersion(Int)
  case unsupportedSchemaVersion(Int)
  case invalidPersistedState
}
