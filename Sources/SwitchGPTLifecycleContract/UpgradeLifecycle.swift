import CryptoKit
import Darwin
import Foundation

// MARK: - Credential-free identity evidence

public enum StableAccountIdentityFingerprintError: Error, Equatable, Sendable {
  case invalidComponent
  case invalidFingerprint
  case unsafeStorage
  case identityChanged
}

/// A stable, non-secret account identity proof.
///
/// The source fields are accepted only in memory. The persisted representation is
/// a SHA-256 digest and never contains an email address, subject, account ID, or
/// credential material. This lets a later client refresh change its auth file
/// without being mistaken for an account switch.
public struct StableAccountIdentityFingerprint: Codable, Equatable, Hashable, Sendable {
  public static let algorithm = "sha256"

  public let rawValue: String

  public init?(rawValue: String) {
    guard
      rawValue.utf8.count == 64,
      rawValue.utf8.allSatisfy({
        ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
      })
    else {
      return nil
    }
    self.rawValue = rawValue
  }

  public init(
    provider: String,
    accountID: String,
    subject: String,
    email: String? = nil
  ) throws {
    let canonical = try Self.canonicalInput(
      provider: provider,
      accountID: accountID,
      subject: subject,
      email: email
    )
    let digest = SHA256.hash(data: Data(canonical.utf8))
    let digits = Array("0123456789abcdef".utf8)
    var bytes = [UInt8]()
    bytes.reserveCapacity(SHA256.byteCount * 2)
    for byte in digest {
      bytes.append(digits[Int(byte >> 4)])
      bytes.append(digits[Int(byte & 0x0F)])
    }
    guard let value = Self(rawValue: String(decoding: bytes, as: UTF8.self)) else {
      throw StableAccountIdentityFingerprintError.invalidFingerprint
    }
    self = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let fingerprint = Self(rawValue: value) else {
      throw StableAccountIdentityFingerprintError.invalidFingerprint
    }
    self = fingerprint
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  fileprivate var encodedStorageValue: Data {
    Data("v1:\(Self.algorithm):\(rawValue)\n".utf8)
  }

  fileprivate init(storageValue data: Data) throws {
    guard
      let value = String(data: data, encoding: .utf8),
      value.hasPrefix("v1:\(Self.algorithm):"),
      value.hasSuffix("\n"),
      value.filter({ $0 == "\n" }).count == 1,
      let fingerprint = Self(
        rawValue: String(value.dropFirst("v1:\(Self.algorithm):".count).dropLast())
      )
    else {
      throw StableAccountIdentityFingerprintError.invalidFingerprint
    }
    self = fingerprint
  }

  private static func canonicalInput(
    provider: String,
    accountID: String,
    subject: String,
    email: String?
  ) throws -> String {
    let provider = try normalizedComponent(provider, lowercased: true)
    let accountID = try normalizedComponent(accountID)
    let subject = try normalizedComponent(subject)
    let email = try email.map { try normalizedComponent($0, lowercased: true) } ?? ""
    return [provider, accountID, subject, email]
      .map { "\($0.utf8.count):\($0)" }
      .joined(separator: "|")
  }

  private static func normalizedComponent(
    _ value: String,
    lowercased: Bool = false
  ) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      trimmed.utf8.count <= 512,
      !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    else {
      throw StableAccountIdentityFingerprintError.invalidComponent
    }
    return lowercased ? trimmed.lowercased() : trimmed
  }
}

public enum StableAccountIdentityFingerprintRecordingOutcome: String, Codable, Equatable, Sendable {
  case recorded
  case alreadyRecorded
}

/// A write-once, private identity baseline used by the offline upgrade ledger.
public final class StableAccountIdentityFingerprintStore {
  private static let directoryName = "identity-fingerprint"
  private static let fileName = "account.fingerprint"

  public let directoryURL: URL
  private let fingerprintURL: URL

  public init(sessionURL: URL) throws {
    do {
      try SecureActivationAttemptStorage.requirePrivateDirectory(sessionURL)
      directoryURL = sessionURL.appendingPathComponent(Self.directoryName, isDirectory: true)
      fingerprintURL = directoryURL.appendingPathComponent(Self.fileName)
      try SecureActivationAttemptStorage.preparePrivateDirectory(directoryURL)
    } catch {
      throw StableAccountIdentityFingerprintError.unsafeStorage
    }
  }

  public static func openExisting(sessionURL: URL) throws -> Self? {
    do {
      try SecureActivationAttemptStorage.requirePrivateDirectory(sessionURL)
      let directoryURL = sessionURL.appendingPathComponent(directoryName, isDirectory: true)
      guard try SecureActivationAttemptStorage.privateDirectoryExists(directoryURL) else {
        return nil
      }
      return try Self(existingSessionURL: sessionURL)
    } catch let error as StableAccountIdentityFingerprintError {
      throw error
    } catch {
      throw StableAccountIdentityFingerprintError.unsafeStorage
    }
  }

  @discardableResult
  public func record(
    _ fingerprint: StableAccountIdentityFingerprint
  ) throws -> StableAccountIdentityFingerprintRecordingOutcome {
    do {
      let created = try SecureActivationAttemptStorage.writeExclusivePrivateFile(
        fingerprint.encodedStorageValue,
        to: fingerprintURL,
        in: directoryURL
      )
      if created { return .recorded }
      guard let existing = try read() else {
        throw StableAccountIdentityFingerprintError.unsafeStorage
      }
      guard existing == fingerprint else {
        throw StableAccountIdentityFingerprintError.identityChanged
      }
      return .alreadyRecorded
    } catch let error as StableAccountIdentityFingerprintError {
      throw error
    } catch {
      throw StableAccountIdentityFingerprintError.unsafeStorage
    }
  }

  public func read() throws -> StableAccountIdentityFingerprint? {
    do {
      guard
        let data = try SecureActivationAttemptStorage.readPrivateFileIfPresent(
          at: fingerprintURL,
          in: directoryURL
        )
      else {
        return nil
      }
      return try StableAccountIdentityFingerprint(storageValue: data)
    } catch let error as StableAccountIdentityFingerprintError {
      throw error
    } catch {
      throw StableAccountIdentityFingerprintError.unsafeStorage
    }
  }

  private init(existingSessionURL sessionURL: URL) throws {
    try SecureActivationAttemptStorage.requirePrivateDirectory(sessionURL)
    directoryURL = sessionURL.appendingPathComponent(Self.directoryName, isDirectory: true)
    fingerprintURL = directoryURL.appendingPathComponent(Self.fileName)
    try SecureActivationAttemptStorage.requirePrivateDirectory(directoryURL)
  }
}

// MARK: - Upgrade bundle descriptors and journal

public enum LifecycleBundleDescriptorError: Error, Equatable, Sendable {
  case invalidValue
}

/// Describes an immutable bundle artifact. `artifactID` is deliberately a
/// separate install slot so an upgrade cannot silently become an in-place write.
public struct LifecycleBundleDescriptor: Codable, Equatable, Sendable {
  public let bundleIdentifier: String
  public let version: String
  public let executableName: String
  public let artifactID: String

  public init(
    bundleIdentifier: String,
    version: String,
    executableName: String,
    artifactID: String
  ) throws {
    guard
      Self.isValidIdentifier(bundleIdentifier, maximumBytes: 128),
      Self.isValidToken(version, maximumBytes: 64),
      Self.isValidExecutableName(executableName),
      Self.isValidToken(artifactID, maximumBytes: 128)
    else {
      throw LifecycleBundleDescriptorError.invalidValue
    }
    self.bundleIdentifier = bundleIdentifier
    self.version = version
    self.executableName = executableName
    self.artifactID = artifactID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      bundleIdentifier: container.decode(String.self, forKey: .bundleIdentifier),
      version: container.decode(String.self, forKey: .version),
      executableName: container.decode(String.self, forKey: .executableName),
      artifactID: container.decode(String.self, forKey: .artifactID)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case bundleIdentifier
    case version
    case executableName
    case artifactID
  }

  private static func isValidIdentifier(_ value: String, maximumBytes: Int) -> Bool {
    guard isValidToken(value, maximumBytes: maximumBytes) else { return false }
    return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
  }

  private static func isValidToken(_ value: String, maximumBytes: Int) -> Bool {
    guard
      !value.isEmpty,
      value.utf8.count <= maximumBytes,
      !value.contains("/"),
      !value.contains("\\"),
      !value.contains("\n"),
      !value.contains("\r"),
      !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    else {
      return false
    }
    return true
  }

  private static func isValidExecutableName(_ value: String) -> Bool {
    isValidToken(value, maximumBytes: 128)
  }
}

public enum LifecycleUpgradePhase: String, Codable, Equatable, Sendable {
  case prepared
  case oldServiceUnregistered
  case candidateInstalled
  case candidateRegistered
  case committed
  case manualRecoveryRequired

  public var isTerminal: Bool {
    switch self {
    case .committed, .manualRecoveryRequired:
      return true
    default:
      return false
    }
  }
}

public enum LifecycleUpgradeFailure: String, Codable, Equatable, Sendable {
  case identityChanged
  case interrupted
  case oldBundleMissing
  case oldServiceUnregistrationUnconfirmed
  case candidateValidationFailed
  case candidateInstallationFailed
  case candidateBundleMissing
  case unregistrationAttemptUnavailable
  case registrationAttemptUnavailable
  case candidateRegistrationUnconfirmed
  case journalUnavailable
}

public struct LifecycleUpgradeRecord: Codable, Equatable, Sendable {
  public let oldBundle: LifecycleBundleDescriptor
  public let candidateBundle: LifecycleBundleDescriptor
  public let identityFingerprint: StableAccountIdentityFingerprint
  public let phase: LifecycleUpgradePhase
  public let failure: LifecycleUpgradeFailure?

  public init(
    oldBundle: LifecycleBundleDescriptor,
    candidateBundle: LifecycleBundleDescriptor,
    identityFingerprint: StableAccountIdentityFingerprint,
    phase: LifecycleUpgradePhase,
    failure: LifecycleUpgradeFailure? = nil
  ) {
    self.oldBundle = oldBundle
    self.candidateBundle = candidateBundle
    self.identityFingerprint = identityFingerprint
    self.phase = phase
    self.failure = failure
  }
}

public enum LifecycleUpgradeJournalError: Error, Equatable, Sendable {
  case unsafeStorage
  case notPrepared
  case alreadyPrepared
  case invalidPhaseTransition
  case inconsistentState
}

/// A write-once phase journal. It intentionally has no reset or delete API.
/// Each phase is a separate marker so a partially written upgrade fails closed.
public final class LifecycleUpgradeJournal {
  private static let directoryName = "upgrade-journal"
  private static let preparedFileName = "prepared.marker"
  private static let oldBundleFileName = "old-bundle"
  private static let candidateBundleFileName = "candidate-bundle"
  private static let oldUnregisteredFileName = "old-service-unregistered.marker"
  private static let candidateInstalledFileName = "candidate-installed.marker"
  private static let candidateRegisteredFileName = "candidate-registered.marker"
  private static let committedFileName = "committed.marker"
  private static let manualRecoveryFileName = "manual-recovery.marker"

  public let directoryURL: URL
  private let fingerprintStore: StableAccountIdentityFingerprintStore

  public init(sessionURL: URL) throws {
    do {
      try SecureActivationAttemptStorage.requirePrivateDirectory(sessionURL)
      directoryURL = sessionURL.appendingPathComponent(Self.directoryName, isDirectory: true)
      try SecureActivationAttemptStorage.preparePrivateDirectory(directoryURL)
      fingerprintStore = try StableAccountIdentityFingerprintStore(sessionURL: sessionURL)
    } catch {
      throw LifecycleUpgradeJournalError.unsafeStorage
    }
  }

  public func load() throws -> LifecycleUpgradeRecord? {
    do {
      try SecureActivationAttemptStorage.requirePrivateDirectory(directoryURL)
      try validateContents()
      let names = try Set(FileManager.default.contentsOfDirectory(atPath: directoryURL.path))
      if names.isEmpty {
        guard try fingerprintStore.read() == nil else {
          throw LifecycleUpgradeJournalError.inconsistentState
        }
        return nil
      }

      guard try readMarker(named: Self.preparedFileName) == Data("v1:prepared\n".utf8) else {
        throw LifecycleUpgradeJournalError.inconsistentState
      }
      guard
        let oldBundleData = try SecureActivationAttemptStorage.readPrivateFileIfPresent(
          at: directoryURL.appendingPathComponent(Self.oldBundleFileName),
          in: directoryURL
        ),
        let candidateBundleData = try SecureActivationAttemptStorage.readPrivateFileIfPresent(
          at: directoryURL.appendingPathComponent(Self.candidateBundleFileName),
          in: directoryURL
        ),
        let oldBundle = try decodeBundle(oldBundleData),
        let candidateBundle = try decodeBundle(candidateBundleData),
        oldBundle.artifactID != candidateBundle.artifactID,
        let fingerprint = try fingerprintStore.read()
      else {
        throw LifecycleUpgradeJournalError.inconsistentState
      }

      let oldUnregistered = try hasMarker(
        Self.oldUnregisteredFileName,
        expected: .oldServiceUnregistered
      )
      let candidateInstalled = try hasMarker(
        Self.candidateInstalledFileName,
        expected: .candidateInstalled
      )
      let candidateRegistered = try hasMarker(
        Self.candidateRegisteredFileName,
        expected: .candidateRegistered
      )
      let committed = try hasMarker(Self.committedFileName, expected: .committed)
      let manualData = try readMarker(named: Self.manualRecoveryFileName)
      let manual = try manualData.map(decodeFailure)

      guard !committed || (candidateRegistered && manual == nil) else {
        throw LifecycleUpgradeJournalError.inconsistentState
      }
      guard !candidateRegistered || candidateInstalled else {
        throw LifecycleUpgradeJournalError.inconsistentState
      }
      guard !candidateInstalled || oldUnregistered else {
        throw LifecycleUpgradeJournalError.inconsistentState
      }
      guard manual == nil || !committed else {
        throw LifecycleUpgradeJournalError.inconsistentState
      }

      let phase: LifecycleUpgradePhase
      if manual != nil {
        phase = .manualRecoveryRequired
      } else if committed {
        phase = .committed
      } else if candidateRegistered {
        phase = .candidateRegistered
      } else if candidateInstalled {
        phase = .candidateInstalled
      } else if oldUnregistered {
        phase = .oldServiceUnregistered
      } else {
        phase = .prepared
      }

      return LifecycleUpgradeRecord(
        oldBundle: oldBundle,
        candidateBundle: candidateBundle,
        identityFingerprint: fingerprint,
        phase: phase,
        failure: manual
      )
    } catch let error as LifecycleUpgradeJournalError {
      throw error
    } catch let error as StableAccountIdentityFingerprintError {
      switch error {
      case .identityChanged:
        throw LifecycleUpgradeJournalError.inconsistentState
      default:
        throw LifecycleUpgradeJournalError.unsafeStorage
      }
    } catch {
      throw LifecycleUpgradeJournalError.unsafeStorage
    }
  }

  public func prepare(
    oldBundle: LifecycleBundleDescriptor,
    candidateBundle: LifecycleBundleDescriptor,
    identityFingerprint: StableAccountIdentityFingerprint
  ) throws {
    guard oldBundle.artifactID != candidateBundle.artifactID else {
      throw LifecycleUpgradeJournalError.inconsistentState
    }
    if try load() != nil {
      throw LifecycleUpgradeJournalError.alreadyPrepared
    }
    let names = try Set(FileManager.default.contentsOfDirectory(atPath: directoryURL.path))
    guard names.isEmpty else {
      throw LifecycleUpgradeJournalError.unsafeStorage
    }

    do {
      try writeExclusive(
        encodeBundle(oldBundle),
        named: Self.oldBundleFileName
      )
      try writeExclusive(
        encodeBundle(candidateBundle),
        named: Self.candidateBundleFileName
      )
      try fingerprintStore.record(identityFingerprint)
      try writeExclusive(Data("v1:prepared\n".utf8), named: Self.preparedFileName)
    } catch let error as LifecycleUpgradeJournalError {
      throw error
    } catch {
      throw LifecycleUpgradeJournalError.unsafeStorage
    }
  }

  public func mark(_ phase: LifecycleUpgradePhase) throws {
    guard phase != .manualRecoveryRequired else {
      throw LifecycleUpgradeJournalError.invalidPhaseTransition
    }
    guard let record = try load() else {
      throw LifecycleUpgradeJournalError.notPrepared
    }
    guard !record.phase.isTerminal else {
      guard record.phase == phase else {
        throw LifecycleUpgradeJournalError.invalidPhaseTransition
      }
      return
    }

    let expectedPrevious: LifecycleUpgradePhase
    let fileName: String
    switch phase {
    case .prepared:
      guard record.phase == .prepared else {
        throw LifecycleUpgradeJournalError.invalidPhaseTransition
      }
      return
    case .oldServiceUnregistered:
      expectedPrevious = .prepared
      fileName = Self.oldUnregisteredFileName
    case .candidateInstalled:
      expectedPrevious = .oldServiceUnregistered
      fileName = Self.candidateInstalledFileName
    case .candidateRegistered:
      expectedPrevious = .candidateInstalled
      fileName = Self.candidateRegisteredFileName
    case .committed:
      expectedPrevious = .candidateRegistered
      fileName = Self.committedFileName
    case .manualRecoveryRequired:
      throw LifecycleUpgradeJournalError.invalidPhaseTransition
    }
    guard record.phase == expectedPrevious else {
      throw LifecycleUpgradeJournalError.invalidPhaseTransition
    }
    try writeExclusive(Data("v1:\(phase.rawValue)\n".utf8), named: fileName)
  }

  public func markManualRecovery(_ failure: LifecycleUpgradeFailure) throws {
    guard let record = try load() else {
      throw LifecycleUpgradeJournalError.notPrepared
    }
    guard !record.phase.isTerminal else {
      guard record.phase == .manualRecoveryRequired, record.failure == failure else {
        throw LifecycleUpgradeJournalError.invalidPhaseTransition
      }
      return
    }
    try writeExclusive(
      Data("v1:\(failure.rawValue)\n".utf8),
      named: Self.manualRecoveryFileName
    )
  }

  private func writeExclusive(_ data: Data, named name: String) throws {
    do {
      _ = try SecureActivationAttemptStorage.writeExclusivePrivateFile(
        data,
        to: directoryURL.appendingPathComponent(name),
        in: directoryURL
      )
    } catch {
      throw LifecycleUpgradeJournalError.unsafeStorage
    }
  }

  private func validateContents() throws {
    let allowed: Set<String> = [
      Self.preparedFileName,
      Self.oldBundleFileName,
      Self.candidateBundleFileName,
      Self.oldUnregisteredFileName,
      Self.candidateInstalledFileName,
      Self.candidateRegisteredFileName,
      Self.committedFileName,
      Self.manualRecoveryFileName,
    ]
    let names = try Set(FileManager.default.contentsOfDirectory(atPath: directoryURL.path))
    guard names.isSubset(of: allowed) else {
      throw LifecycleUpgradeJournalError.unsafeStorage
    }
  }

  private func hasMarker(
    _ name: String,
    expected phase: LifecycleUpgradePhase
  ) throws -> Bool {
    guard let data = try readMarker(named: name) else { return false }
    guard data == Data("v1:\(phase.rawValue)\n".utf8) else {
      throw LifecycleUpgradeJournalError.inconsistentState
    }
    return true
  }

  private func readMarker(named name: String) throws -> Data? {
    do {
      return try SecureActivationAttemptStorage.readPrivateFileIfPresent(
        at: directoryURL.appendingPathComponent(name),
        in: directoryURL
      )
    } catch {
      throw LifecycleUpgradeJournalError.unsafeStorage
    }
  }

  private func encodeBundle(_ bundle: LifecycleBundleDescriptor) -> Data {
    Data(
      "v1:\(bundle.bundleIdentifier)\n\(bundle.version)\n\(bundle.executableName)\n\(bundle.artifactID)\n"
        .utf8
    )
  }

  private func decodeBundle(_ data: Data) throws -> LifecycleBundleDescriptor? {
    guard
      let value = String(data: data, encoding: .utf8),
      value.hasPrefix("v1:"),
      value.hasSuffix("\n")
    else {
      throw LifecycleUpgradeJournalError.inconsistentState
    }
    let components = value.dropFirst(3).split(separator: "\n", omittingEmptySubsequences: false)
    guard components.count == 5, components.last?.isEmpty == true else {
      throw LifecycleUpgradeJournalError.inconsistentState
    }
    do {
      return try LifecycleBundleDescriptor(
        bundleIdentifier: String(components[0]),
        version: String(components[1]),
        executableName: String(components[2]),
        artifactID: String(components[3])
      )
    } catch {
      throw LifecycleUpgradeJournalError.inconsistentState
    }
  }

  private func decodeFailure(_ data: Data) throws -> LifecycleUpgradeFailure {
    guard
      let value = String(data: data, encoding: .utf8),
      value.hasPrefix("v1:"),
      value.hasSuffix("\n"),
      value.filter({ $0 == "\n" }).count == 1,
      let failure = LifecycleUpgradeFailure(
        rawValue: String(value.dropFirst(3).dropLast())
      )
    else {
      throw LifecycleUpgradeJournalError.inconsistentState
    }
    return failure
  }
}

// MARK: - ChatGPT-free upgrade controller

public struct LifecycleUpgradeServiceSnapshot: Codable, Equatable, Sendable {
  public let status: RecoveryServiceStatus
  public let registeredBundle: LifecycleBundleDescriptor?

  public init(
    status: RecoveryServiceStatus,
    registeredBundle: LifecycleBundleDescriptor?
  ) {
    self.status = status
    self.registeredBundle = registeredBundle
  }
}

public protocol LifecycleUpgradePlatform: AnyObject {
  func readSnapshot() throws -> LifecycleUpgradeServiceSnapshot
  func validateCandidate(
    _ candidateBundle: LifecycleBundleDescriptor,
    preserving oldBundle: LifecycleBundleDescriptor
  ) throws
  func unregisterCurrentService() throws
  func installCandidate(
    _ candidateBundle: LifecycleBundleDescriptor,
    preserving oldBundle: LifecycleBundleDescriptor
  ) throws
  func verifyExecutable(_ bundle: LifecycleBundleDescriptor) throws -> Bool
  func registerCandidate(_ candidateBundle: LifecycleBundleDescriptor) throws
}

public protocol LifecycleUpgradeAttemptRecording: LifecycleActivationAttemptRecording {
  func hasReservation(_ operation: LifecycleActivationOperation) throws -> Bool
}

extension PersistentActivationAttemptRecorder: LifecycleUpgradeAttemptRecording {}
extension TemporaryActivationAttemptRecorder: LifecycleUpgradeAttemptRecording {
  public func hasReservation(_ operation: LifecycleActivationOperation) throws -> Bool {
    do {
      return try SecureActivationAttemptStorage(
        existingRootURL: rootURL
      ).hasReservation(operation)
    } catch {
      throw TemporaryActivationAttemptRecorderError.unsafeStorage
    }
  }
}

public enum LifecycleUpgradeOutcome: String, Codable, Equatable, Sendable {
  case upgradeCommitted
  case upgradeAlreadyCommitted
  case upgradeNotStarted
  case preflightFailed
  case candidateValidationFailed
  case oldServiceUnregistrationUnconfirmed
  case candidateInstallationFailed
  case candidateRegistrationUnconfirmed
  case manualRecoveryRequired
  case registrationAttemptUnavailable
  case unregistrationAttemptUnavailable
  case ledgerUnavailable
}

public struct LifecycleUpgradeReport: Codable, Equatable, Sendable {
  public let outcome: LifecycleUpgradeOutcome
  public let phase: LifecycleUpgradePhase?
  public let failure: LifecycleUpgradeFailure?
  public let oldBundleRetained: Bool?
  public let snapshot: LifecycleUpgradeServiceSnapshot?

  public init(
    outcome: LifecycleUpgradeOutcome,
    phase: LifecycleUpgradePhase? = nil,
    failure: LifecycleUpgradeFailure? = nil,
    oldBundleRetained: Bool? = nil,
    snapshot: LifecycleUpgradeServiceSnapshot? = nil
  ) {
    self.outcome = outcome
    self.phase = phase
    self.failure = failure
    self.oldBundleRetained = oldBundleRetained
    self.snapshot = snapshot
  }
}

/// Executes only the offline, recovery-helper upgrade protocol. It has no
/// ChatGPT adapter and never accepts a target account or credential path.
public final class LifecycleUpgradeController {
  private let platform: any LifecycleUpgradePlatform
  private let attemptRecorder: any LifecycleUpgradeAttemptRecording
  private let journal: LifecycleUpgradeJournal

  public init(
    platform: any LifecycleUpgradePlatform,
    attemptRecorder: any LifecycleUpgradeAttemptRecording,
    journal: LifecycleUpgradeJournal
  ) {
    self.platform = platform
    self.attemptRecorder = attemptRecorder
    self.journal = journal
  }

  public func run(
    oldBundle: LifecycleBundleDescriptor,
    candidateBundle: LifecycleBundleDescriptor,
    identityFingerprint: StableAccountIdentityFingerprint
  ) -> LifecycleUpgradeReport {
    do {
      if let existing = try journal.load() {
        return LifecycleUpgradeReport(
          outcome: existing.phase == .committed
            ? .upgradeAlreadyCommitted
            : .manualRecoveryRequired,
          phase: existing.phase,
          failure: existing.failure
        )
      }
      guard oldBundle.artifactID != candidateBundle.artifactID else {
        return LifecycleUpgradeReport(outcome: .preflightFailed)
      }
      let initial = try platform.readSnapshot()
      guard
        initial.status == .enabled,
        initial.registeredBundle == oldBundle,
        try platform.verifyExecutable(oldBundle)
      else {
        return LifecycleUpgradeReport(outcome: .preflightFailed, snapshot: initial)
      }
      do {
        try platform.validateCandidate(candidateBundle, preserving: oldBundle)
      } catch {
        return LifecycleUpgradeReport(outcome: .candidateValidationFailed)
      }
      try journal.prepare(
        oldBundle: oldBundle,
        candidateBundle: candidateBundle,
        identityFingerprint: identityFingerprint
      )

      guard try attemptRecorder.reserve(.unregistration) else {
        try? journal.markManualRecovery(.unregistrationAttemptUnavailable)
        return reportAfterManual(
          outcome: .unregistrationAttemptUnavailable,
          fallback: .unregistrationAttemptUnavailable
        )
      }
      do { try platform.unregisterCurrentService() } catch { }
      guard
        let afterUnregistration = try? platform.readSnapshot(),
        afterUnregistration.status == .notRegistered,
        afterUnregistration.registeredBundle == nil,
        (try? platform.verifyExecutable(oldBundle)) == true
      else {
        return try fail(
          .oldServiceUnregistrationUnconfirmed,
          failure: .oldServiceUnregistrationUnconfirmed
        )
      }
      try journal.mark(.oldServiceUnregistered)

      do {
        try platform.installCandidate(candidateBundle, preserving: oldBundle)
      } catch {
        return try fail(.candidateInstallationFailed, failure: .candidateInstallationFailed)
      }
      guard
        (try? platform.verifyExecutable(oldBundle)) == true,
        (try? platform.verifyExecutable(candidateBundle)) == true
      else {
        return try fail(.candidateInstallationFailed, failure: .candidateBundleMissing)
      }
      try journal.mark(.candidateInstalled)

      guard try attemptRecorder.reserve(.registration) else {
        return try fail(.registrationAttemptUnavailable, failure: .registrationAttemptUnavailable)
      }
      do { try platform.registerCandidate(candidateBundle) } catch { }
      guard
        let afterRegistration = try? platform.readSnapshot(),
        afterRegistration.status == .enabled,
        afterRegistration.registeredBundle == candidateBundle,
        (try? platform.verifyExecutable(oldBundle)) == true,
        (try? platform.verifyExecutable(candidateBundle)) == true
      else {
        return try fail(
          .candidateRegistrationUnconfirmed,
          failure: .candidateRegistrationUnconfirmed
        )
      }
      try journal.mark(.candidateRegistered)
      try journal.mark(.committed)
      return LifecycleUpgradeReport(
        outcome: .upgradeCommitted,
        phase: .committed,
        oldBundleRetained: true,
        snapshot: afterRegistration
      )
    } catch let error as LifecycleUpgradeJournalError {
      switch error {
      case .unsafeStorage, .inconsistentState:
        return LifecycleUpgradeReport(outcome: .ledgerUnavailable)
      case .notPrepared, .alreadyPrepared, .invalidPhaseTransition:
        return LifecycleUpgradeReport(outcome: .manualRecoveryRequired)
      }
    } catch {
      return LifecycleUpgradeReport(outcome: .ledgerUnavailable)
    }
  }

  /// Recovers only by observing and finalizing an already proven candidate.
  /// It never calls register, unregister, install, or a retry path.
  public func recover(
    currentIdentityFingerprint: StableAccountIdentityFingerprint
  ) -> LifecycleUpgradeReport {
    do {
      guard let record = try journal.load() else {
        return LifecycleUpgradeReport(outcome: .upgradeNotStarted)
      }
      if record.phase == .committed {
        return LifecycleUpgradeReport(
          outcome: .upgradeAlreadyCommitted,
          phase: record.phase,
          failure: record.failure
        )
      }
      if record.phase == .manualRecoveryRequired {
        return LifecycleUpgradeReport(
          outcome: .manualRecoveryRequired,
          phase: record.phase,
          failure: record.failure
        )
      }
      guard record.identityFingerprint == currentIdentityFingerprint else {
        return try fail(.manualRecoveryRequired, failure: .identityChanged)
      }

      guard
        let snapshot = try? platform.readSnapshot(),
        (try? platform.verifyExecutable(record.oldBundle)) == true,
        (try? platform.verifyExecutable(record.candidateBundle)) == true
      else {
        return try fail(.manualRecoveryRequired, failure: .interrupted)
      }

      guard
        snapshot.status == .enabled,
        snapshot.registeredBundle == record.candidateBundle,
        try attemptRecorder.hasReservation(.registration)
      else {
        return try fail(.manualRecoveryRequired, failure: .interrupted)
      }

      if record.phase == .candidateInstalled {
        try journal.mark(.candidateRegistered)
      }
      try journal.mark(.committed)
      return LifecycleUpgradeReport(
        outcome: .upgradeCommitted,
        phase: .committed,
        oldBundleRetained: true,
        snapshot: snapshot
      )
    } catch let error as LifecycleUpgradeJournalError {
      switch error {
      case .unsafeStorage, .inconsistentState:
        return LifecycleUpgradeReport(outcome: .ledgerUnavailable)
      case .notPrepared, .alreadyPrepared, .invalidPhaseTransition:
        return LifecycleUpgradeReport(outcome: .manualRecoveryRequired)
      }
    } catch {
      return LifecycleUpgradeReport(outcome: .ledgerUnavailable)
    }
  }

  private func fail(
    _ outcome: LifecycleUpgradeOutcome,
    failure: LifecycleUpgradeFailure
  ) throws -> LifecycleUpgradeReport {
    try journal.markManualRecovery(failure)
    let record = try journal.load()
    guard failure != .identityChanged else {
      return LifecycleUpgradeReport(
        outcome: outcome,
        phase: record?.phase,
        failure: failure
      )
    }
    let oldBundleRetained: Bool?
    if let oldBundle = record?.oldBundle {
      oldBundleRetained = try? platform.verifyExecutable(oldBundle)
    } else {
      oldBundleRetained = nil
    }
    return LifecycleUpgradeReport(
      outcome: outcome,
      phase: record?.phase,
      failure: failure,
      oldBundleRetained: oldBundleRetained,
      snapshot: try? platform.readSnapshot()
    )
  }

  private func reportAfterManual(
    outcome: LifecycleUpgradeOutcome,
    fallback: LifecycleUpgradeOutcome
  ) -> LifecycleUpgradeReport {
    guard let record = try? journal.load() else {
      return LifecycleUpgradeReport(outcome: fallback)
    }
    return LifecycleUpgradeReport(
      outcome: outcome,
      phase: record.phase,
      failure: record.failure
    )
  }

}
