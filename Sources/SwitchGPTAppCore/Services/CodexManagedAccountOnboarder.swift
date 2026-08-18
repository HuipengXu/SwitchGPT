import Darwin
import Foundation
import SwitchGPTDesktopIntegration

public protocol ManagedAccountOnboarding: Sendable {
  func signIn() async throws -> String
  func preserveAccount(from codexHomePath: String) throws -> String
  func discardManagedAccount(at path: String) throws
}

public enum ManagedAccountOnboardingError: Error, Equatable, LocalizedError, Sendable {
  case missingCodexBinary
  case insecureStorage
  case loginFailed
  case loginTimedOut

  public var errorDescription: String? {
    switch self {
    case .missingCodexBinary:
      return "The ChatGPT sign-in component was not found."
    case .insecureStorage:
      return "SwitchGPT could not create private account storage."
    case .loginFailed:
      return "Sign-in did not complete."
    case .loginTimedOut:
      return "Sign-in timed out. Please try again."
    }
  }
}

public struct CodexManagedAccountOnboarder: ManagedAccountOnboarding, Sendable {
  public let codexBinaryURL: URL
  public let timeout: TimeInterval
  public let accountsRootURL: URL

  public init(
    codexBinaryURL: URL = URL(
      fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"
    ),
    timeout: TimeInterval = 10 * 60,
    accountsRootURL: URL? = nil
  ) {
    self.codexBinaryURL = codexBinaryURL.standardizedFileURL
    self.timeout = timeout
    if let accountsRootURL {
      self.accountsRootURL = accountsRootURL.standardizedFileURL
    } else {
      let applicationSupport =
        FileManager.default.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
          "Library/Application Support",
          isDirectory: true
        )
      self.accountsRootURL =
        applicationSupport
        .appendingPathComponent("SwitchGPT", isDirectory: true)
        .appendingPathComponent("Accounts", isDirectory: true)
    }
  }

  public func signIn() async throws -> String {
    guard FileManager.default.isExecutableFile(atPath: codexBinaryURL.path) else {
      throw ManagedAccountOnboardingError.missingCodexBinary
    }
    let accountDirectory = try createPrivateAccountDirectory()
    let processBox = LoginProcessBox()
    do {
      try await withTaskCancellationHandler {
        try await Task.detached(priority: .userInitiated) {
          let process = Process()
          process.executableURL = codexBinaryURL
          process.arguments = ["login"]
          var environment = ProcessInfo.processInfo.environment
          environment["CODEX_HOME"] = accountDirectory.path
          environment.removeValue(forKey: "OPENAI_API_KEY")
          environment.removeValue(forKey: "CODEX_API_KEY")
          environment.removeValue(forKey: "CODEX_ACCESS_TOKEN")
          process.environment = environment
          process.standardInput = FileHandle.nullDevice
          process.standardOutput = FileHandle.nullDevice
          process.standardError = FileHandle.nullDevice
          processBox.install(process)
          try Task.checkCancellation()
          do {
            try process.run()
          } catch {
            throw ManagedAccountOnboardingError.loginFailed
          }

          let deadline = Date().addingTimeInterval(timeout)
          while process.isRunning, Date() < deadline {
            if Task.isCancelled {
              process.terminate()
              throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(100))
          }
          if process.isRunning {
            process.terminate()
            throw ManagedAccountOnboardingError.loginTimedOut
          }
          guard process.terminationStatus == 0 else {
            throw ManagedAccountOnboardingError.loginFailed
          }
        }.value
      } onCancel: {
        processBox.terminate()
      }
      try Self.validatePrivateDirectory(accountDirectory)
      return accountDirectory.path
    } catch {
      try? FileManager.default.removeItem(at: accountDirectory)
      throw error
    }
  }

  public func preserveAccount(from codexHomePath: String) throws -> String {
    let sourceDirectory = URL(fileURLWithPath: codexHomePath, isDirectory: true)
      .standardizedFileURL
    let sourceAuthenticationURL = sourceDirectory.appendingPathComponent("auth.json")
    let accountDirectory = try createPrivateAccountDirectory()
    do {
      try SecureAuthenticationFileInstaller.archivePrivateAuthenticationFile(
        from: sourceAuthenticationURL,
        to: accountDirectory.appendingPathComponent("auth.json")
      )
      try Self.validatePrivateDirectory(accountDirectory)
      return accountDirectory.path
    } catch {
      try? FileManager.default.removeItem(at: accountDirectory)
      throw ManagedAccountOnboardingError.insecureStorage
    }
  }

  public func discardManagedAccount(at path: String) throws {
    let candidate = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let root = accountsRootURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolved = candidate.resolvingSymlinksInPath()
    guard resolved.deletingLastPathComponent() == root,
      UUID(uuidString: resolved.lastPathComponent) != nil
    else {
      throw ManagedAccountOnboardingError.insecureStorage
    }
    try Self.validatePrivateDirectory(candidate)
    try FileManager.default.removeItem(at: candidate)
  }

  private func createPrivateAccountDirectory() throws -> URL {
    let appRoot = accountsRootURL.deletingLastPathComponent()
    try Self.preparePrivateDirectory(appRoot)
    try Self.preparePrivateDirectory(accountsRootURL)
    let accountDirectory = accountsRootURL.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    do {
      try FileManager.default.createDirectory(
        at: accountDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try Self.validatePrivateDirectory(accountDirectory)
      return accountDirectory
    } catch {
      throw ManagedAccountOnboardingError.insecureStorage
    }
  }

  private static func preparePrivateDirectory(_ url: URL) throws {
    var status = stat()
    if url.path.withCString({ lstat($0, &status) }) == 0 {
      try validatePrivateDirectory(url)
      return
    }
    guard errno == ENOENT else { throw ManagedAccountOnboardingError.insecureStorage }
    do {
      try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try validatePrivateDirectory(url)
    } catch {
      throw ManagedAccountOnboardingError.insecureStorage
    }
  }

  private static func validatePrivateDirectory(_ url: URL) throws {
    var status = stat()
    guard url.path.withCString({ lstat($0, &status) }) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == geteuid(),
      status.st_mode & 0o777 == 0o700
    else {
      throw ManagedAccountOnboardingError.insecureStorage
    }
  }
}

private final class LoginProcessBox: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?

  func install(_ process: Process) {
    lock.withLock { self.process = process }
  }

  func terminate() {
    lock.withLock {
      if process?.isRunning == true { process?.terminate() }
    }
  }
}
