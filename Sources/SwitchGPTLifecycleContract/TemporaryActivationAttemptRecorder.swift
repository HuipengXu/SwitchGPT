import Foundation

public enum TemporaryActivationAttemptRecorderError: Error, Equatable, Sendable {
  case unsafeRoot
  case unsafeStorage
}

/// A durable, cross-process attempt budget restricted to `switchgpt-safety-*` temporary fixtures.
/// It cannot be pointed at an application support directory or any real authentication state.
public final class TemporaryActivationAttemptRecorder: LifecycleActivationAttemptRecording {
  public let rootURL: URL
  public let directoryURL: URL
  private let storage: SecureActivationAttemptStorage

  public init(rootURL: URL) throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let candidate = rootURL.standardizedFileURL
    let resolvedCandidate = candidate.resolvingSymlinksInPath()
    let temporaryComponents = temporaryRoot.pathComponents
    let candidateComponents = resolvedCandidate.pathComponents

    guard
      candidateComponents.count > temporaryComponents.count,
      Array(candidateComponents.prefix(temporaryComponents.count)) == temporaryComponents,
      candidateComponents[temporaryComponents.count].hasPrefix("switchgpt-safety-")
    else {
      throw TemporaryActivationAttemptRecorderError.unsafeRoot
    }

    self.rootURL = candidate
    do {
      storage = try SecureActivationAttemptStorage(rootURL: candidate)
    } catch SecureActivationAttemptStorageError.unsafeStorage {
      throw TemporaryActivationAttemptRecorderError.unsafeStorage
    }
    directoryURL = storage.directoryURL
  }

  public func reserve(_ operation: LifecycleActivationOperation) throws -> Bool {
    do {
      return try storage.reserve(operation)
    } catch SecureActivationAttemptStorageError.unsafeStorage {
      throw TemporaryActivationAttemptRecorderError.unsafeStorage
    }
  }
}
