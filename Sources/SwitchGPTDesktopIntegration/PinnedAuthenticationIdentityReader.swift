import CryptoKit
import Foundation
import SwitchGPTSafetyCore

public final class PinnedAuthenticationIdentityReader: InstalledIdentityReading {
  private let authenticationFileURL: URL

  public init(authenticationFileURL: URL) {
    self.authenticationFileURL = authenticationFileURL.standardizedFileURL
  }

  public func currentIdentity() throws -> IdentityID {
    let data = try SecureAuthenticationFileInstaller.readPrivateAuthenticationFile(
      at: authenticationFileURL
    )
    try SecureAuthenticationFileInstaller.validateAuthenticationPayload(data)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let tokens = object["tokens"] as? [String: Any],
      let idToken = tokens["id_token"] as? String,
      let email = Self.email(fromJWT: idToken)
    else {
      throw DesktopIntegrationError.invalidAuthenticationPayload
    }
    let digest = SHA256.hash(data: Data(email.lowercased().utf8))
    let shortHash = digest.map { String(format: "%02x", $0) }.joined().prefix(12)
    guard let identity = IdentityID(rawValue: String(shortHash)) else {
      throw DesktopIntegrationError.invalidAuthenticationPayload
    }
    return identity
  }

  private static func email(fromJWT token: String) -> String? {
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3 else { return nil }
    var payload = String(segments[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = payload.count % 4
    if remainder != 0 {
      payload += String(repeating: "=", count: 4 - remainder)
    }
    guard
      let data = Data(base64Encoded: payload),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let email = object["email"] as? String,
      !email.isEmpty
    else {
      return nil
    }
    return email
  }
}
