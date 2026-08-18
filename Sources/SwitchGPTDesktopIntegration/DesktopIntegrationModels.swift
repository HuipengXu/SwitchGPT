import Foundation
import SwitchGPTSafetyCore

public struct DesktopCredentialProfile: Equatable, Sendable {
  public let identity: IdentityID
  public let authenticationFileURL: URL

  public init(identity: IdentityID, authenticationFileURL: URL) {
    self.identity = identity
    self.authenticationFileURL = authenticationFileURL.standardizedFileURL
  }
}

public enum DesktopIntegrationError: Error, Equatable, LocalizedError, Sendable {
  case missingProfile
  case duplicateProfile
  case invalidAuthenticationFile
  case insecureAuthenticationFile
  case authenticationFileTooLarge
  case invalidAuthenticationPayload
  case identityMismatch
  case missingRecoverySnapshot
  case desktopDidNotTerminate
  case desktopDidNotLaunch

  public var errorDescription: String? {
    switch self {
    case .missingProfile:
      "The selected account profile is unavailable."
    case .duplicateProfile:
      "More than one profile has the same identity."
    case .invalidAuthenticationFile:
      "The authentication state is not a private regular file."
    case .insecureAuthenticationFile:
      "The authentication state has unsafe ownership or permissions."
    case .authenticationFileTooLarge:
      "The authentication state is unexpectedly large."
    case .invalidAuthenticationPayload:
      "The authentication state has an invalid structure."
    case .identityMismatch:
      "The installed authentication identity does not match the expected account."
    case .missingRecoverySnapshot:
      "The original account snapshot is unavailable; automatic recovery is disabled."
    case .desktopDidNotTerminate:
      "ChatGPT did not exit before the safety deadline."
    case .desktopDidNotLaunch:
      "ChatGPT did not launch before the safety deadline."
    }
  }
}

public protocol DesktopProcessControlling: AnyObject {
  func isRunning() throws -> Bool
  func terminateAndWait() throws
  func launchAndWait() throws
}

public protocol InstalledIdentityReading: AnyObject {
  func currentIdentity() throws -> IdentityID
}

public protocol AuthenticationStateInstalling: AnyObject {
  func snapshotActiveStateIfNeeded() throws
  func hasRecoverySnapshot() throws -> Bool
  func installAuthenticationFile(from sourceURL: URL) throws
  func restoreRecoverySnapshot() throws
}
