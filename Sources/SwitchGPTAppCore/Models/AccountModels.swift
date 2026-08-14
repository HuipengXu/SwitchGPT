import Foundation

public struct AccountID: Hashable, Codable, Sendable, Identifiable {
  public let rawValue: String

  public var id: String { rawValue }

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }
}

public enum AccountAccent: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case orange
  case blue
  case purple
  case green
}

public enum AccountSource: Codable, Equatable, Hashable, Sendable {
  case mock
  case codexHome(path: String)
}

public struct UsageWindow: Codable, Equatable, Hashable, Sendable {
  public let usedPercent: Int
  public let resetAt: Date

  public var remainingPercent: Int {
    100 - usedPercent
  }

  public init(usedPercent: Int, resetAt: Date) {
    self.usedPercent = min(max(usedPercent, 0), 100)
    self.resetAt = resetAt
  }
}

public struct AccountUsage: Codable, Equatable, Hashable, Sendable {
  public let weekly: UsageWindow
  public let fiveHour: UsageWindow?

  public init(weekly: UsageWindow, fiveHour: UsageWindow? = nil) {
    self.weekly = weekly
    self.fiveHour = fiveHour
  }
}

public struct AccountRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: AccountID
  public let displayName: String
  public let detail: String
  public let planName: String
  public let symbolName: String
  public let accent: AccountAccent
  public let source: AccountSource
  public let identityHash: String?
  public var usage: AccountUsage

  public init(
    id: AccountID,
    displayName: String,
    detail: String,
    planName: String,
    symbolName: String,
    accent: AccountAccent,
    usage: AccountUsage,
    source: AccountSource = .mock,
    identityHash: String? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.detail = detail
    self.planName = planName
    self.symbolName = symbolName
    self.accent = accent
    self.source = source
    self.identityHash = identityHash
    self.usage = usage
  }
}

public enum MockAccountCatalog {
  public static func accounts(now: Date = Date()) -> [AccountRecord] {
    let calendar = Calendar.autoupdatingCurrent
    let personalWeeklyReset = calendar.date(byAdding: .day, value: 4, to: now) ?? now
    let workWeeklyReset = calendar.date(byAdding: .day, value: 3, to: now) ?? now

    return [
      AccountRecord(
        id: AccountID("personal"),
        displayName: "Personal",
        detail: "Private workspace",
        planName: "ChatGPT Plus",
        symbolName: "person.crop.circle.fill",
        accent: .orange,
        usage: AccountUsage(
          weekly: UsageWindow(usedPercent: 21, resetAt: personalWeeklyReset)
        )
      ),
      AccountRecord(
        id: AccountID("work"),
        displayName: "Work",
        detail: "Team workspace",
        planName: "ChatGPT Plus",
        symbolName: "briefcase.circle.fill",
        accent: .blue,
        usage: AccountUsage(
          weekly: UsageWindow(usedPercent: 64, resetAt: workWeeklyReset)
        )
      )
    ]
  }

  public static func makeAdditionalAccount(
    displayName: String,
    detail: String,
    ordinal: Int,
    now: Date = Date()
  ) -> AccountRecord {
    let calendar = Calendar.autoupdatingCurrent
    let resetDays = 2 + (ordinal % 4)
    let weeklyReset = calendar.date(byAdding: .day, value: resetDays, to: now) ?? now
    let accentIndex = max(0, ordinal) % AccountAccent.allCases.count
    let usedPercent = min(20 + (max(0, ordinal - 2) * 17), 84)

    return AccountRecord(
      id: AccountID("mock-" + UUID().uuidString.lowercased()),
      displayName: displayName,
      detail: detail,
      planName: "ChatGPT Plus",
      symbolName: "person.crop.circle.badge.plus",
      accent: AccountAccent.allCases[accentIndex],
      usage: AccountUsage(
        weekly: UsageWindow(usedPercent: usedPercent, resetAt: weeklyReset)
      )
    )
  }
}
