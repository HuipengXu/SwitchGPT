import Foundation
import Security
import SwitchGPTLifecycleContract

public enum RecoveryAgentRegistrationPreflightError: Error, Equatable, Sendable {
  case invalidBundle
  case invalidSignature
  case codeIdentifierMismatch
  case missingTeamIdentifier
  case teamIdentifierMismatch
}

/// Read-only validation required before a first registration attempt may be reserved.
public struct RecoveryAgentRegistrationPreflight: LifecycleActivationPreflighting {
  private let bundleURL: URL

  public init(bundleURL: URL) {
    self.bundleURL = bundleURL.standardizedFileURL
  }

  public func validateForRegistration() throws {
    do {
      try LifecycleBundleContract.validate(bundleURL: bundleURL)
    } catch {
      throw RecoveryAgentRegistrationPreflightError.invalidBundle
    }

    let helperURL = bundleURL.appendingPathComponent(
      "Contents/Library/LaunchServices/\(LifecycleBundleContract.recoveryExecutableName)"
    )
    let bundleCode = try staticCode(at: bundleURL)
    let helperCode = try staticCode(at: helperURL)
    let validationFlags = SecCSFlags(
      rawValue:
        kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
    )
    guard
      SecStaticCodeCheckValidity(bundleCode, validationFlags, nil) == errSecSuccess,
      SecStaticCodeCheckValidity(helperCode, validationFlags, nil) == errSecSuccess
    else {
      throw RecoveryAgentRegistrationPreflightError.invalidSignature
    }

    let bundleTeam = try teamIdentifier(for: bundleCode)
    let helperTeam = try teamIdentifier(for: helperCode)
    guard bundleTeam == helperTeam else {
      throw RecoveryAgentRegistrationPreflightError.teamIdentifierMismatch
    }

    guard
      try codeIdentifier(for: bundleCode) == LifecycleBundleContract.bundleIdentifier,
      try codeIdentifier(for: helperCode) == LaunchAgentContract.label
    else {
      throw RecoveryAgentRegistrationPreflightError.codeIdentifierMismatch
    }
  }

  private func staticCode(at url: URL) throws -> SecStaticCode {
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
      let code
    else {
      throw RecoveryAgentRegistrationPreflightError.invalidSignature
    }
    return code
  }

  private func teamIdentifier(for code: SecStaticCode) throws -> String {
    let dictionary = try signingInformation(for: code)
    guard
      let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier] as? String,
      !teamIdentifier.isEmpty
    else {
      throw RecoveryAgentRegistrationPreflightError.missingTeamIdentifier
    }
    return teamIdentifier
  }

  private func codeIdentifier(for code: SecStaticCode) throws -> String {
    let dictionary = try signingInformation(for: code)
    guard
      let identifier = dictionary[kSecCodeInfoIdentifier] as? String,
      !identifier.isEmpty
    else {
      throw RecoveryAgentRegistrationPreflightError.codeIdentifierMismatch
    }
    return identifier
  }

  private func signingInformation(for code: SecStaticCode) throws -> [CFString: Any] {
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &information
      ) == errSecSuccess,
      let dictionary = information as? [CFString: Any]
    else {
      throw RecoveryAgentRegistrationPreflightError.invalidSignature
    }
    return dictionary
  }
}
