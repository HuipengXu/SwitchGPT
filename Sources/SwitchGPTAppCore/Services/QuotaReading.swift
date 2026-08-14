import Foundation

public protocol QuotaReading: Sendable {
  func fetchUsage(for accounts: [AccountRecord]) async throws -> [AccountID: AccountUsage]
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

  public func fetchUsage(for accounts: [AccountRecord]) async throws -> [AccountID: AccountUsage] {
    let now = Date()
    let calendar = Calendar.autoupdatingCurrent

    return Dictionary(uniqueKeysWithValues: accounts.enumerated().map { index, account in
      let weeklyUsed = index == 0 ? 21 : min(64 + ((index - 1) * 13), 84)
      let resetDays = index == 0 ? 4 : 3 + ((index - 1) % 4)
      let weeklyReset = calendar.date(byAdding: .day, value: resetDays, to: now) ?? now

      return (
        account.id,
        AccountUsage(
          weekly: UsageWindow(usedPercent: weeklyUsed, resetAt: weeklyReset)
        )
      )
    })
  }
}
