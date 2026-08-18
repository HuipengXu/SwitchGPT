import Foundation

public enum PersistentActivationAttemptRecorderError: Error, Equatable, Sendable {
  case unsafeRoot
  case unsafeStorage
}

public enum LifecycleActivationValidationSession: String, Codable, Equatable, Sendable {
  case immediateLifecycle = "phase-b-immediate-lifecycle"
  case rebootLifecycle = "phase-c-reboot-lifecycle"
  case upgradeLifecycle = "phase-d-upgrade-lifecycle"
}

/// Durable one-registration/one-unregistration budget for a named validation session.
/// There is intentionally no API to erase or reset a session.
public final class PersistentActivationAttemptRecorder: LifecycleActivationAttemptRecording {
  public static let applicationSupportDirectoryName =
    "com.switchgpt.lifecycle-validation"

  public let session: LifecycleActivationValidationSession
  public let sessionURL: URL
  public let directoryURL: URL
  private let storage: SecureActivationAttemptStorage

  /// Creates or reopens one of the fixed validation phases under private Application Support.
  public convenience init(session: LifecycleActivationValidationSession) throws {
    let applicationSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    ).standardizedFileURL.resolvingSymlinksInPath()
    try self.init(
      session: session,
      parentURL: applicationSupport,
      parentDirectoryName: Self.applicationSupportDirectoryName,
      createIfMissing: true
    )
  }

  /// Opens a fixed validation session without creating any directory or file.
  public static func openExisting(
    session: LifecycleActivationValidationSession
  ) throws -> PersistentActivationAttemptRecorder? {
    let applicationSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    ).standardizedFileURL.resolvingSymlinksInPath()
    let applicationDirectory = applicationSupport.appendingPathComponent(
      Self.applicationSupportDirectoryName,
      isDirectory: true
    )
    let sessionURL =
      applicationDirectory
      .appendingPathComponent("system-activation", isDirectory: true)
      .appendingPathComponent("sessions", isDirectory: true)
      .appendingPathComponent(session.rawValue, isDirectory: true)
    guard try SecureActivationAttemptStorage.privateDirectoryExists(sessionURL) else {
      return nil
    }
    return try PersistentActivationAttemptRecorder(
      session: session,
      parentURL: applicationSupport,
      parentDirectoryName: Self.applicationSupportDirectoryName,
      createIfMissing: false
    )
  }

  /// Test-only initializer. The root must be a private `switchgpt-safety-*` temp fixture.
  convenience init(
    testRootURL: URL,
    session: LifecycleActivationValidationSession
  ) throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let candidate = testRootURL.standardizedFileURL
    let resolvedCandidate = candidate.resolvingSymlinksInPath()
    let temporaryComponents = temporaryRoot.pathComponents
    let candidateComponents = resolvedCandidate.pathComponents
    guard
      candidateComponents.count > temporaryComponents.count,
      Array(candidateComponents.prefix(temporaryComponents.count)) == temporaryComponents,
      candidateComponents[temporaryComponents.count].hasPrefix("switchgpt-safety-")
    else {
      throw PersistentActivationAttemptRecorderError.unsafeRoot
    }
    do {
      try SecureActivationAttemptStorage.requirePrivateDirectory(candidate)
    } catch {
      throw PersistentActivationAttemptRecorderError.unsafeStorage
    }
    try self.init(
      session: session,
      parentURL: candidate,
      parentDirectoryName: "persistent-activation-validation",
      createIfMissing: true
    )
  }

  private init(
    session: LifecycleActivationValidationSession,
    parentURL: URL,
    parentDirectoryName: String,
    createIfMissing: Bool
  ) throws {
    self.session = session
    let applicationDirectory = parentURL.appendingPathComponent(
      parentDirectoryName,
      isDirectory: true
    )
    let validationDirectory = applicationDirectory.appendingPathComponent(
      "system-activation",
      isDirectory: true
    )
    let sessionsDirectory = validationDirectory.appendingPathComponent(
      "sessions",
      isDirectory: true
    )
    sessionURL = sessionsDirectory.appendingPathComponent(
      session.rawValue,
      isDirectory: true
    )

    do {
      if createIfMissing {
        try SecureActivationAttemptStorage.preparePrivateDirectory(applicationDirectory)
        try SecureActivationAttemptStorage.preparePrivateDirectory(validationDirectory)
        try SecureActivationAttemptStorage.preparePrivateDirectory(sessionsDirectory)
        try SecureActivationAttemptStorage.preparePrivateDirectory(sessionURL)
        storage = try SecureActivationAttemptStorage(rootURL: sessionURL)
      } else {
        try SecureActivationAttemptStorage.requirePrivateDirectory(applicationDirectory)
        try SecureActivationAttemptStorage.requirePrivateDirectory(validationDirectory)
        try SecureActivationAttemptStorage.requirePrivateDirectory(sessionsDirectory)
        try SecureActivationAttemptStorage.requirePrivateDirectory(sessionURL)
        storage = try SecureActivationAttemptStorage(existingRootURL: sessionURL)
      }
    } catch {
      throw PersistentActivationAttemptRecorderError.unsafeStorage
    }
    directoryURL = storage.directoryURL
  }

  public func reserve(_ operation: LifecycleActivationOperation) throws -> Bool {
    do {
      return try storage.reserve(operation)
    } catch {
      throw PersistentActivationAttemptRecorderError.unsafeStorage
    }
  }

  public func hasReservation(_ operation: LifecycleActivationOperation) throws -> Bool {
    do {
      return try storage.hasReservation(operation)
    } catch {
      throw PersistentActivationAttemptRecorderError.unsafeStorage
    }
  }
}
