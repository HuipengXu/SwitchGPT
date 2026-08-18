import CryptoKit
import Foundation

struct CodexAccountMetadata: Equatable, Sendable {
  let identityHash: String
  let email: String
  let planName: String
}

enum CodexAccountDecoder {
  static func decode(from data: Data) throws -> CodexAccountMetadata {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw QuotaReadingError.invalidProtocolResponse
    }
    let account = (object["account"] as? [String: Any]) ?? object
    guard let email = account["email"] as? String, !email.isEmpty else {
      throw QuotaReadingError.invalidProtocolResponse
    }
    let displayEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !displayEmail.isEmpty else {
      throw QuotaReadingError.invalidProtocolResponse
    }

    let rawPlan = (account["planType"] as? String) ?? (account["plan_type"] as? String)
    let digest = SHA256.hash(data: Data(email.utf8))
    return CodexAccountMetadata(
      identityHash: digest.map { String(format: "%02x", $0) }.joined().prefix(12).description,
      email: displayEmail,
      planName: ChatGPTMembership.displayName(for: rawPlan)
    )
  }
}

public enum ChatGPTMembership {
  public static func displayName(for rawValue: String?) -> String {
    switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "free":
      return "Free"
    case "go":
      return "Go"
    case "plus":
      return "Plus"
    case "pro":
      return "Pro"
    case "prolite":
      return "Pro Lite"
    case "team":
      return "Team"
    case "self_serve_business_prolite", "self_serve_business_usage_based", "business":
      return "Business"
    case "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based", "enterprise":
      return "Enterprise"
    case "edu":
      return "Edu"
    default:
      return "Unknown"
    }
  }
}
