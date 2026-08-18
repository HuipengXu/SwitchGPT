import Foundation

public protocol QuotaReading: Sendable {
  func fetchSnapshots(for accounts: [AccountRecord]) async throws
    -> [AccountID: AccountQuotaSnapshot]
}

extension QuotaReading {
  public func fetchUsage(for accounts: [AccountRecord]) async throws -> [AccountID: AccountUsage] {
    try await fetchSnapshots(for: accounts).mapValues(\.usage)
  }
}

public struct AccountQuotaSnapshot: Equatable, Sendable {
  public let email: String?
  public let planName: String
  public let usage: AccountUsage

  public init(email: String? = nil, planName: String, usage: AccountUsage) {
    self.email = email
    self.planName = planName
    self.usage = usage
  }
}

public struct ReadOnlyAccountProbe: Equatable, Sendable {
  public let identityHash: String
  public let email: String?
  public let planName: String
  public let usage: AccountUsage

  public init(
    identityHash: String,
    email: String? = nil,
    planName: String = "Unknown",
    usage: AccountUsage
  ) {
    self.identityHash = identityHash
    self.email = email
    self.planName = planName
    self.usage = usage
  }
}

public protocol ReadOnlyAccountProbing: Sendable {
  func probe(codexHomePath: String) async throws -> ReadOnlyAccountProbe
}

public enum QuotaReadingError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedSource
  case invalidHomePath
  case insecureHomePermissions
  case missingAuthenticationFile
  case invalidAuthenticationFile
  case identityNotPinned
  case identityMismatch
  case missingCodexBinary
  case processLaunchFailed
  case timedOut
  case invalidProtocolResponse
  case missingRateLimit

  public var errorDescription: String? {
    switch self {
    case .unsupportedSource:
      return "This account is not configured for read-only quota access."
    case .invalidHomePath:
      return "The configured account home is invalid."
    case .insecureHomePermissions:
      return "The configured account home permissions are too broad."
    case .missingAuthenticationFile:
      return "The configured account has no authentication file."
    case .invalidAuthenticationFile:
      return "The configured authentication file is not a regular private file."
    case .identityNotPinned:
      return "The account identity has not been pinned for read-only access."
    case .identityMismatch:
      return "The configured account identity does not match the staged home."
    case .missingCodexBinary:
      return "The bundled Codex app-server binary was not found."
    case .processLaunchFailed:
      return "The read-only app-server could not be started."
    case .timedOut:
      return "The read-only quota request timed out."
    case .invalidProtocolResponse:
      return "The read-only app-server returned an invalid response."
    case .missingRateLimit:
      return "The app-server did not return a Codex rate limit."
    }
  }
}

public struct MockQuotaReader: QuotaReading {
  public init() {}

  public func fetchSnapshots(for accounts: [AccountRecord]) async throws
    -> [AccountID: AccountQuotaSnapshot]
  {
    let now = Date()
    let calendar = Calendar.autoupdatingCurrent

    return Dictionary(
      uniqueKeysWithValues: accounts.enumerated().map { index, account in
        let weeklyUsed = index == 0 ? 21 : min(64 + ((index - 1) * 13), 84)
        let resetDays = index == 0 ? 4 : 3 + ((index - 1) % 4)
        let weeklyReset = calendar.date(byAdding: .day, value: resetDays, to: now) ?? now

        return (
          account.id,
          AccountQuotaSnapshot(
            email: account.email,
            planName: account.planName,
            usage: AccountUsage(
              weekly: UsageWindow(usedPercent: weeklyUsed, resetAt: weeklyReset)
            )
          )
        )
      })
  }
}

public struct UnavailableAccountProbe: ReadOnlyAccountProbing {
  public init() {}

  public func probe(codexHomePath: String) async throws -> ReadOnlyAccountProbe {
    throw QuotaReadingError.unsupportedSource
  }
}
