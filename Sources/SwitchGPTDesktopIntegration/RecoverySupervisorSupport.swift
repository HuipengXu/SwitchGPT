import Darwin
import Foundation
import Security
import SwitchGPTSafetyCore

public enum RecoverySupervisorError: Error, Equatable, Sendable {
  case invalidTransactionPath
  case helperUnavailable
  case invalidHelperSignature
  case helperExitedBeforeReady
  case helperReadinessTimedOut
}

public enum RecoveryTransactionPathContract {
  public static func validate(candidate: URL, transactionsRoot: URL) throws -> URL {
    let root = transactionsRoot.standardizedFileURL.resolvingSymlinksInPath()
    let transaction = candidate.standardizedFileURL.resolvingSymlinksInPath()
    let rootComponents = root.pathComponents
    let transactionComponents = transaction.pathComponents
    guard
      transactionComponents.count == rootComponents.count + 1,
      Array(transactionComponents.prefix(rootComponents.count)) == rootComponents,
      UUID(uuidString: transaction.lastPathComponent) != nil
    else {
      throw RecoverySupervisorError.invalidTransactionPath
    }
    return transaction
  }

  public static func validateExistingPrivateDirectory(_ url: URL) throws {
    var status = stat()
    guard url.path.withCString({ lstat($0, &status) }) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == geteuid(),
      status.st_mode & 0o777 == 0o700
    else {
      throw RecoverySupervisorError.invalidTransactionPath
    }
  }
}

public final class ProcessOneShotRecoverySupervisor: OneShotRecoverySupervisor {
  private let helperURL: URL
  private let transactionDirectoryURL: URL
  private let readinessURL: URL
  private let timeout: TimeInterval
  private let expectedTeamIdentifier: String
  private let expectedSigningIdentifier: String
  private var process: Process?

  public init(
    helperURL: URL,
    transactionDirectoryURL: URL,
    expectedTeamIdentifier: String,
    expectedSigningIdentifier: String = "SwitchGPTRecoverySupervisor",
    timeout: TimeInterval = 5
  ) {
    self.helperURL = helperURL.standardizedFileURL
    self.transactionDirectoryURL = transactionDirectoryURL.standardizedFileURL
    self.readinessURL = transactionDirectoryURL.appendingPathComponent("recovery.ready")
    self.expectedTeamIdentifier = expectedTeamIdentifier
    self.expectedSigningIdentifier = expectedSigningIdentifier
    self.timeout = timeout
  }

  public func armAndWaitUntilReady() throws {
    guard process == nil, FileManager.default.isExecutableFile(atPath: helperURL.path) else {
      throw RecoverySupervisorError.helperUnavailable
    }
    try EmbeddedRecoveryHelperContract.validate(
      helperURL: helperURL,
      expectedTeamIdentifier: expectedTeamIdentifier,
      expectedSigningIdentifier: expectedSigningIdentifier
    )
    let process = Process()
    process.executableURL = helperURL
    process.arguments = ["recover-current", transactionDirectoryURL.path]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
      try process.run()
    } catch {
      throw RecoverySupervisorError.helperUnavailable
    }
    self.process = process

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if FileManager.default.fileExists(atPath: readinessURL.path) { return }
      if !process.isRunning {
        throw RecoverySupervisorError.helperExitedBeforeReady
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
    if process.isRunning { process.terminate() }
    throw RecoverySupervisorError.helperReadinessTimedOut
  }

  public func waitUntilFinished(timeout: TimeInterval = 5) throws {
    guard let process else { throw RecoverySupervisorError.helperUnavailable }
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    guard !process.isRunning, process.terminationStatus == 0 else {
      throw RecoverySupervisorError.helperExitedBeforeReady
    }
  }
}

public enum EmbeddedRecoveryHelperContract {
  public static func validate(
    helperURL: URL,
    expectedTeamIdentifier: String,
    expectedSigningIdentifier: String
  ) throws {
    guard !expectedTeamIdentifier.isEmpty, !expectedSigningIdentifier.isEmpty else {
      throw RecoverySupervisorError.invalidHelperSignature
    }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(helperURL as CFURL, [], &code) == errSecSuccess,
      let code,
      SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
        == errSecSuccess
    else {
      throw RecoverySupervisorError.invalidHelperSignature
    }
    var signingInformation: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &signingInformation
      ) == errSecSuccess,
      let information = signingInformation as? [CFString: Any],
      information[kSecCodeInfoTeamIdentifier] as? String == expectedTeamIdentifier,
      information[kSecCodeInfoIdentifier] as? String == expectedSigningIdentifier
    else {
      throw RecoverySupervisorError.invalidHelperSignature
    }
  }
}

public enum RecoveryReadinessMarker {
  public static func create(at url: URL) throws {
    let descriptor = url.path.withCString {
      open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
    }
    guard descriptor >= 0 else {
      throw RecoverySupervisorError.helperUnavailable
    }
    defer { close(descriptor) }
    let bytes = Array("ready\n".utf8)
    guard bytes.withUnsafeBytes({ write(descriptor, $0.baseAddress, $0.count) }) == bytes.count,
      fsync(descriptor) == 0
    else {
      throw RecoverySupervisorError.helperUnavailable
    }
  }
}
