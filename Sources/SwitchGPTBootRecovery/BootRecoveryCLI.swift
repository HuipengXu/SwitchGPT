import Darwin
import Foundation
import OSLog
import SwitchGPTLifecycleContract
import SwitchGPTSafetyCore

@main
enum BootRecoveryCLI {
  private static let fixtureRootEnvironmentKey = "SWITCHGPT_SAFETY_ROOT"
  private static let logger = Logger(
    subsystem: LifecycleBundleContract.bundleIdentifier,
    category: "BootRecovery"
  )

  static func main() {
    let outcome = execute()
    logger.notice("outcome=\(outcome.rawValue, privacy: .public)")
    FileHandle.standardOutput.write(Data("\(outcome.rawValue)\n".utf8))
    exit(0)
  }

  private static func execute() -> BootRecoveryOutcome {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments == [BootRecoveryEntry.command] else { return .invalidInvocation }
    guard let rootPath = ProcessInfo.processInfo.environment[fixtureRootEnvironmentKey] else {
      return executeRebootDeliveryValidation()
    }

    do {
      let sandbox = try BootFixtureSandbox(path: rootPath)
      let store = try TransactionStore(directoryURL: sandbox.transactionDirectoryURL)
      let desktop = try BootFixtureDesktop(
        rootURL: sandbox.rootURL,
        directoryURL: sandbox.desktopDirectoryURL
      )
      return BootRecoveryEntry.run(arguments: arguments, store: store, desktop: desktop)
    } catch {
      return .unsafeState
    }
  }

  private static func executeRebootDeliveryValidation() -> BootRecoveryOutcome {
    do {
      guard
        let recorder = try PersistentActivationAttemptRecorder.openExisting(
          session: .rebootLifecycle
        ),
        let evidenceStore = try RebootDeliveryEvidenceStore.openExisting(
          sessionURL: recorder.sessionURL
        )
      else {
        return .inactive
      }
      let sessionLock: LifecycleActivationSessionLock
      do {
        sessionLock = try LifecycleActivationSessionLock(sessionURL: recorder.sessionURL)
      } catch SafetyError.lockUnavailable {
        return .sessionBusy
      }
      defer { sessionLock.release() }
      return RebootDeliveryEntry.run(
        recorder: recorder,
        evidenceStore: evidenceStore,
        bootSession: try SystemBootSessionIdentifier.current()
      )
    } catch {
      return .unsafeState
    }
  }
}

private enum BootFixtureError: Error {
  case unsafeRoot
  case fixtureMissing
}

private struct BootFixtureSandbox {
  let rootURL: URL

  init(path: String) throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let candidate = URL(fileURLWithPath: path, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()

    let temporaryComponents = temporaryRoot.pathComponents
    let candidateComponents = candidate.pathComponents
    guard
      candidateComponents.count > temporaryComponents.count,
      Array(candidateComponents.prefix(temporaryComponents.count)) == temporaryComponents,
      candidateComponents[temporaryComponents.count].hasPrefix("switchgpt-safety-")
    else {
      throw BootFixtureError.unsafeRoot
    }
    rootURL = candidate
  }

  var desktopDirectoryURL: URL {
    rootURL.appendingPathComponent("desktop", isDirectory: true)
  }

  var transactionDirectoryURL: URL {
    rootURL.appendingPathComponent("transaction", isDirectory: true)
  }
}

private struct BootFixtureDesktopState: Codable {
  var installedIdentity: IdentityID
  var isRunning: Bool
  var startsByIdentity: [String: Int]
  var stopCount: Int
}

private final class BootFixtureDesktop: TransactionDesktop {
  private let rootURL: URL
  private let directoryURL: URL
  private let stateURL: URL

  init(rootURL: URL, directoryURL: URL) throws {
    self.rootURL = rootURL
    self.directoryURL = directoryURL
    stateURL = directoryURL.appendingPathComponent("desktop.json")
    try validatePaths()
  }

  func isRunning() throws -> Bool {
    try read().isRunning
  }

  func currentIdentity() throws -> IdentityID {
    try read().installedIdentity
  }

  func stop() throws {
    var state = try read()
    state.isRunning = false
    state.stopCount += 1
    try write(state)
  }

  func install(identity: IdentityID) throws {
    var state = try read()
    state.installedIdentity = identity
    try write(state)
  }

  func start() throws {
    var state = try read()
    state.isRunning = true
    state.startsByIdentity[state.installedIdentity.rawValue, default: 0] += 1
    try write(state)
  }

  private func read() throws -> BootFixtureDesktopState {
    try validatePaths()
    return try JSONDecoder().decode(
      BootFixtureDesktopState.self,
      from: Data(contentsOf: stateURL)
    )
  }

  private func write(_ state: BootFixtureDesktopState) throws {
    try validatePaths()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: stateURL, options: .atomic)
    guard stateURL.path.withCString({ chmod($0, 0o600) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private func validatePaths() throws {
    let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedDirectory = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedState = stateURL.standardizedFileURL.resolvingSymlinksInPath()
    guard
      isDescendant(resolvedDirectory, of: resolvedRoot),
      isDescendant(resolvedState, of: resolvedDirectory),
      try isPrivateDirectory(resolvedRoot),
      try isPrivateDirectory(resolvedDirectory),
      try isPrivateRegularFile(resolvedState)
    else {
      throw BootFixtureError.unsafeRoot
    }
  }

  private func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
    let ancestorComponents = ancestor.pathComponents
    let candidateComponents = candidate.pathComponents
    return candidateComponents.count > ancestorComponents.count
      && Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
  }

  private func isPrivateDirectory(_ url: URL) throws -> Bool {
    let status = try fileStatus(at: url)
    return status.st_mode & S_IFMT == S_IFDIR
      && status.st_uid == geteuid()
      && status.st_mode & 0o777 == 0o700
  }

  private func isPrivateRegularFile(_ url: URL) throws -> Bool {
    let status = try fileStatus(at: url)
    return status.st_mode & S_IFMT == S_IFREG
      && status.st_uid == geteuid()
      && status.st_nlink == 1
      && status.st_mode & 0o777 == 0o600
  }

  private func fileStatus(at url: URL) throws -> stat {
    var status = stat()
    guard url.path.withCString({ lstat($0, &status) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return status
  }
}
