import Darwin
import Foundation

enum SimulatorError: Error {
  case usage
  case unsafeRoot
  case fixtureAlreadyExists
  case fixtureMissing
  case invalidCheckpoint
  case childFailed(command: String, status: Int32)
  case assertionFailed(String)
}

struct SimulatorSandbox {
  let rootURL: URL

  init(path: String) throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let candidate = URL(fileURLWithPath: path, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()

    let temporaryComponents = temporaryRoot.pathComponents
    let candidateComponents = candidate.pathComponents
    guard
      candidateComponents.count > temporaryComponents.count,
      Array(candidateComponents.prefix(temporaryComponents.count)) == temporaryComponents
    else {
      throw SimulatorError.unsafeRoot
    }

    let firstRelativeComponent = candidateComponents[temporaryComponents.count]
    guard firstRelativeComponent.hasPrefix("switchgpt-safety-") else {
      throw SimulatorError.unsafeRoot
    }

    rootURL = candidate
  }

  var desktopDirectoryURL: URL {
    rootURL.appendingPathComponent("desktop", isDirectory: true)
  }

  var transactionDirectoryURL: URL {
    rootURL.appendingPathComponent("transaction", isDirectory: true)
  }

  var lockReadyURL: URL {
    rootURL.appendingPathComponent("lock-ready")
  }

  func supervisorReadyURL(index: Int) -> URL {
    rootURL.appendingPathComponent("supervisor-ready-\(index)")
  }

  func supervisorDoneURL(index: Int) -> URL {
    rootURL.appendingPathComponent("supervisor-done-\(index)")
  }

  func createRoot() throws {
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try setMode(0o700, at: rootURL)
  }

  func setMode(_ mode: mode_t, at url: URL) throws {
    let result = url.path.withCString { chmod($0, mode) }
    guard result == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}
