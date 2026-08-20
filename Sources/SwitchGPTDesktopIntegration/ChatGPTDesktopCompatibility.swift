import Foundation

public struct ChatGPTDesktopVersion: Hashable, Sendable {
  public let version: String
  public let build: String

  public init(version: String, build: String) {
    self.version = version
    self.build = build
  }
}

/// Records whether a signed ChatGPT Desktop version has completed SwitchGPT's
/// controlled compatibility validation. This classification is intentionally
/// separate from trust validation: callers must still verify the bundle path,
/// signature, team, and signing identifier before an account switch can start.
public enum ChatGPTDesktopCompatibilityAssessment: Equatable, Sendable {
  case validated(ChatGPTDesktopVersion)
  case unvalidated(version: String?, build: String?)

  public var isValidated: Bool {
    if case .validated = self {
      return true
    }
    return false
  }
}

public enum ChatGPTDesktopCompatibility {
  // Real switching and rollback were validated against this exact signed client.
  public static let supportedVersions: Set<ChatGPTDesktopVersion> = [
    ChatGPTDesktopVersion(version: "26.810.52044", build: "6662")
  ]

  public static func assessment(
    version: String?,
    build: String?
  ) -> ChatGPTDesktopCompatibilityAssessment {
    let normalizedVersion = normalized(version)
    let normalizedBuild = normalized(build)
    guard let normalizedVersion, let normalizedBuild else {
      return .unvalidated(version: normalizedVersion, build: normalizedBuild)
    }

    let candidate = ChatGPTDesktopVersion(
      version: normalizedVersion,
      build: normalizedBuild
    )
    return supportedVersions.contains(candidate)
      ? .validated(candidate)
      : .unvalidated(version: normalizedVersion, build: normalizedBuild)
  }

  public static func supports(version: String?, build: String?) -> Bool {
    assessment(version: version, build: build).isValidated
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}
