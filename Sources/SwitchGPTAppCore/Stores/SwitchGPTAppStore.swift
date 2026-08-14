import Foundation
import Observation

public enum SwitchGPTActivity: Equatable, Sendable {
  case ready
  case refreshing
  case simulating(targetName: String)
  case success(message: String)
  case failure(message: String)

  public var message: String {
    switch self {
    case .ready:
      return "Ready"
    case .refreshing:
      return "Refreshing usage…"
    case let .simulating(targetName):
      return "Simulating switch to " + targetName + "…"
    case let .success(message), let .failure(message):
      return message
    }
  }

  public var isBusy: Bool {
    switch self {
    case .refreshing, .simulating:
      return true
    case .ready, .success, .failure:
      return false
    }
  }

  public var isFailure: Bool {
    if case .failure = self {
      return true
    }
    return false
  }
}

@MainActor
@Observable
public final class SwitchGPTAppStore {
  public private(set) var accounts: [AccountRecord]
  public private(set) var currentAccountID: AccountID
  public private(set) var activity: SwitchGPTActivity = .ready
  public private(set) var lastRefreshedAt: Date?
  public private(set) var lastPersistenceError: String?

  private let quotaReader: any QuotaReading
  private let persistence: any PreviewStatePersisting

  public init(
    quotaReader: any QuotaReading = MockQuotaReader(),
    now: Date = Date(),
    persistence: any PreviewStatePersisting = NoopPreviewStateStore()
  ) {
    let defaultAccounts = MockAccountCatalog.accounts(now: now)
    let loadedState: PreviewState?
    do {
      loadedState = try persistence.load()
    } catch {
      loadedState = nil
    }

    if let state = loadedState, Self.isUsablePreviewState(state)
    {
      self.accounts = state.accounts
      self.currentAccountID = state.currentAccountID
      self.lastRefreshedAt = state.lastRefreshedAt
    } else {
      self.accounts = defaultAccounts
      self.currentAccountID = defaultAccounts[0].id
      self.lastRefreshedAt = nil
    }
    self.quotaReader = quotaReader
    self.persistence = persistence
    self.lastPersistenceError = nil
  }

  public var currentAccount: AccountRecord? {
    accounts.first { $0.id == currentAccountID }
  }

  @discardableResult
  public func addMockAccount(displayName: String, detail: String) -> AccountID? {
    guard !activity.isBusy else { return nil }

    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }

    let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    let account = MockAccountCatalog.makeAdditionalAccount(
      displayName: name,
      detail: trimmedDetail.isEmpty ? "Additional workspace" : trimmedDetail,
      ordinal: accounts.count
    )
    accounts.append(account)
    if persistState() {
      activity = .success(message: "Added mock account: " + account.displayName)
    }
    return account.id
  }

  public func removeMockAccount(_ accountID: AccountID) {
    guard !activity.isBusy,
      accounts.count > 1,
      let index = accounts.firstIndex(where: { $0.id == accountID }),
      accountID != currentAccountID
    else { return }

    guard case .mock = accounts[index].source else { return }
    let removed = accounts.remove(at: index)
    if persistState() {
      activity = .success(message: "Removed mock account: " + removed.displayName)
    }
  }

  public func refresh() async {
    guard !activity.isBusy else { return }

    activity = .refreshing
    do {
      let usageByAccount = try await quotaReader.fetchUsage(for: accounts)
      accounts = accounts.map { account in
        var updated = account
        if let usage = usageByAccount[account.id] {
          updated.usage = usage
        }
        return updated
      }
      lastRefreshedAt = Date()
      if persistState() {
        activity = .success(message: "Usage refreshed")
      }
    } catch {
      activity = .failure(message: "Could not refresh usage")
    }
  }

  public func simulateSwitch(to targetID: AccountID) async {
    guard let target = accounts.first(where: { $0.id == targetID }), target.id != currentAccountID else {
      return
    }
    guard !activity.isBusy else { return }

    activity = .simulating(targetName: target.displayName)
    do {
      try await Task.sleep(nanoseconds: 450_000_000)
    } catch {
      activity = .ready
      return
    }
    currentAccountID = target.id
    if persistState() {
      activity = .success(message: "Simulation complete — no desktop account changed")
    }
  }

  public func resetActivity() {
    guard !activity.isBusy else { return }
    activity = .ready
  }

  private func persistState() -> Bool {
    let state = PreviewState(
      accounts: accounts,
      currentAccountID: currentAccountID,
      lastRefreshedAt: lastRefreshedAt
    )
    do {
      try persistence.save(state)
      lastPersistenceError = nil
      return true
    } catch {
      lastPersistenceError = error.localizedDescription
      activity = .failure(message: "Could not save local preview state")
      return false
    }
  }

  private static func isUsablePreviewState(_ state: PreviewState) -> Bool {
    guard !state.accounts.isEmpty,
          state.accounts.contains(where: { $0.id == state.currentAccountID })
    else { return false }

    return state.accounts.allSatisfy { account in
      guard case .mock = account.source else { return false }
      return account.identityHash == nil
    }
  }
}
