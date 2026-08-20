import Foundation
import Observation

public enum SwitchGPTActivity: Equatable, Sendable {
  case ready
  case refreshing
  case simulating(targetName: String)
  case switching(targetName: String)
  case success(message: String)
  case failure(message: String)

  public var message: String {
    switch self {
    case .ready:
      return "Ready"
    case .refreshing:
      return "Refreshing usage…"
    case .simulating(let targetName):
      return "Simulating switch to " + targetName + "…"
    case .switching(let targetName):
      return "Switching ChatGPT to " + targetName + "…"
    case .success(let message), .failure(let message):
      return message
    }
  }

  public var isBusy: Bool {
    switch self {
    case .refreshing, .simulating, .switching:
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

  public var blocksAccountOnboarding: Bool {
    switch self {
    case .simulating, .switching:
      return true
    case .ready, .refreshing, .success, .failure:
      return false
    }
  }
}

public enum AccountOnboardingActivity: Equatable, Sendable {
  case idle
  case signingIn
  case failure(message: String)

  public var isInProgress: Bool {
    if case .signingIn = self { return true }
    return false
  }

  public var failureMessage: String? {
    if case .failure(let message) = self { return message }
    return nil
  }
}

@MainActor
@Observable
public final class SwitchGPTAppStore {
  public private(set) var accounts: [AccountRecord]
  public private(set) var currentAccountID: AccountID?
  public private(set) var activity: SwitchGPTActivity = .ready
  public private(set) var accountOnboardingActivity: AccountOnboardingActivity = .idle
  public private(set) var lastRefreshedAt: Date?
  public private(set) var lastPersistenceError: String?

  private let quotaReader: any QuotaReading
  private let accountProbe: any ReadOnlyAccountProbing
  private let accountOnboarder: any ManagedAccountOnboarding
  private let persistence: any PreviewStatePersisting

  public init(
    quotaReader: any QuotaReading = MixedQuotaReader(),
    accountProbe: any ReadOnlyAccountProbing = CodexAppServerQuotaReader(),
    accountOnboarder: any ManagedAccountOnboarding = CodexManagedAccountOnboarder(),
    now: Date = Date(),
    persistence: any PreviewStatePersisting = NoopPreviewStateStore(),
    initialAccounts: [AccountRecord]? = nil
  ) {
    let defaultAccounts = initialAccounts ?? MockAccountCatalog.accounts(now: now)
    let startsWithoutDemoAccounts = initialAccounts?.isEmpty == true
    let loadedState: PreviewState?
    do {
      loadedState = try persistence.load()
    } catch {
      loadedState = nil
    }

    var migratedMockAccounts = false
    if let state = loadedState, Self.isUsablePreviewState(state) {
      if startsWithoutDemoAccounts {
        let realAccounts = state.accounts.filter { account in
          if case .mock = account.source { return false }
          return true
        }
        migratedMockAccounts = realAccounts.count != state.accounts.count
        self.accounts = realAccounts
        self.currentAccountID = state.currentAccountID.flatMap { currentID in
          realAccounts.contains(where: { $0.id == currentID }) ? currentID : nil
        }
        self.lastRefreshedAt = state.lastRefreshedAt
      } else {
        self.accounts = state.accounts
        self.currentAccountID = state.currentAccountID
        self.lastRefreshedAt = state.lastRefreshedAt
      }
    } else {
      self.accounts = defaultAccounts
      self.currentAccountID = defaultAccounts.first?.id
      self.lastRefreshedAt = nil
    }
    self.quotaReader = quotaReader
    self.accountProbe = accountProbe
    self.accountOnboarder = accountOnboarder
    self.persistence = persistence
    self.lastPersistenceError = nil

    if startsWithoutDemoAccounts, migratedMockAccounts {
      do {
        if accounts.isEmpty {
          try persistence.remove()
        } else {
          try persistence.save(
            PreviewState(
              accounts: accounts,
              currentAccountID: currentAccountID,
              lastRefreshedAt: lastRefreshedAt
            )
          )
        }
      } catch {
        self.lastPersistenceError = error.localizedDescription
      }
    }
  }

  @discardableResult
  public func signInAccount() async -> AccountID? {
    guard !accountOnboardingActivity.isInProgress,
      !activity.blocksAccountOnboarding
    else { return nil }
    let realAccountCount = accounts.filter {
      if case .codexHome = $0.source { return true }
      return false
    }.count
    accountOnboardingActivity = .signingIn
    var managedPath: String?
    let previousLastRefreshedAt = lastRefreshedAt
    do {
      let path = try await accountOnboarder.signIn()
      managedPath = path
      try Task.checkCancellation()
      let probe = try await accountProbe.probe(codexHomePath: path)
      try Task.checkCancellation()
      guard !accounts.contains(where: { $0.identityHash == probe.identityHash }) else {
        try? accountOnboarder.discardManagedAccount(at: path)
        accountOnboardingActivity = .failure(message: "This account is already configured")
        return nil
      }
      let fallbackName = "Account \(realAccountCount + 1)"
      let account = AccountRecord(
        id: AccountID("account-" + UUID().uuidString.lowercased()),
        displayName: probe.email ?? fallbackName,
        email: probe.email,
        detail: "",
        planName: probe.planName,
        symbolName: "person.crop.circle",
        accent: AccountAccent.allCases[accounts.count % AccountAccent.allCases.count],
        usage: probe.usage,
        source: .codexHome(path: path),
        identityHash: probe.identityHash
      )
      accounts.append(account)
      lastRefreshedAt = Date()
      guard persistState() else {
        accounts.removeAll { $0.id == account.id }
        lastRefreshedAt = previousLastRefreshedAt
        try? accountOnboarder.discardManagedAccount(at: path)
        managedPath = nil
        accountOnboardingActivity = .failure(message: "Could not save the added account")
        return nil
      }
      accountOnboardingActivity = .idle
      return account.id
    } catch is CancellationError {
      if let managedPath { try? accountOnboarder.discardManagedAccount(at: managedPath) }
      accountOnboardingActivity = .idle
      return nil
    } catch {
      if let managedPath { try? accountOnboarder.discardManagedAccount(at: managedPath) }
      if Task.isCancelled {
        accountOnboardingActivity = .idle
      } else {
        accountOnboardingActivity = .failure(message: error.localizedDescription)
      }
      return nil
    }
  }

  public func resetAccountOnboardingActivity() {
    guard !accountOnboardingActivity.isInProgress else { return }
    accountOnboardingActivity = .idle
  }

  @discardableResult
  public func addReadOnlyAccount(
    displayName: String,
    detail: String,
    codexHomePath: String
  ) async -> AccountID? {
    guard !activity.isBusy else { return nil }
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let path = codexHomePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, path.hasPrefix("/") else { return nil }

    activity = .refreshing
    do {
      let probe = try await accountProbe.probe(codexHomePath: path)
      guard !accounts.contains(where: { $0.identityHash == probe.identityHash }) else {
        activity = .failure(message: "This account is already configured")
        return nil
      }
      let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
      let account = AccountRecord(
        id: AccountID("account-" + UUID().uuidString.lowercased()),
        displayName: name,
        email: probe.email,
        detail: trimmedDetail.isEmpty ? "Read-only quota" : trimmedDetail,
        planName: probe.planName,
        symbolName: "person.crop.circle",
        accent: AccountAccent.allCases[accounts.count % AccountAccent.allCases.count],
        usage: probe.usage,
        source: .codexHome(path: path),
        identityHash: probe.identityHash
      )
      accounts.append(account)
      lastRefreshedAt = Date()
      if persistState() {
        activity = .success(message: "Added read-only account: " + account.displayName)
      }
      return account.id
    } catch {
      activity = .failure(message: error.localizedDescription)
      return nil
    }
  }

  public var currentAccount: AccountRecord? {
    guard let currentAccountID else { return nil }
    return accounts.first { $0.id == currentAccountID }
  }

  /// Replaces only the untouched two-account demo catalog with the currently active local
  /// account. The probe stages auth.json and explicitly disables refresh-token mutation.
  public func bootstrapCurrentAccountIfNeeded() async {
    guard !activity.isBusy else { return }
    guard accounts.isEmpty || Self.isUntouchedDemoCatalog(accounts) else { return }
    let activeHome = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .path
    activity = .refreshing
    do {
      let probe = try await accountProbe.probe(codexHomePath: activeHome)
      let account = AccountRecord(
        id: AccountID("account-" + UUID().uuidString.lowercased()),
        displayName: probe.email ?? "Current account",
        email: probe.email,
        detail: "",
        planName: probe.planName,
        symbolName: "person.crop.circle",
        accent: .orange,
        usage: probe.usage,
        source: .codexHome(path: activeHome),
        identityHash: probe.identityHash
      )
      accounts = [account]
      currentAccountID = account.id
      lastRefreshedAt = Date()
      if persistState() {
        activity = .success(message: "Current account quota loaded")
      }
    } catch {
      NSLog("[SwitchGPT/quota] current account bootstrap failed: %@", String(describing: error))
      activity = .failure(message: "Could not load the current account quota")
    }
  }

  /// Migrates the active desktop account away from the mutable ~/.codex location into an
  /// app-managed private profile. A real switch is blocked until this preservation succeeds.
  public func preserveActiveAccountForSwitchingIfNeeded() async {
    guard !activity.isBusy else { return }
    let activeHome = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .standardizedFileURL
    guard
      let index = accounts.firstIndex(where: { account in
        guard case .codexHome(let path) = account.source else { return false }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL == activeHome
      }), let expectedIdentity = accounts[index].identityHash
    else { return }

    activity = .refreshing
    var managedPath: String?
    do {
      let activeProbe = try await accountProbe.probe(codexHomePath: activeHome.path)
      guard activeProbe.identityHash == expectedIdentity else {
        activity = .failure(
          message: "The active ChatGPT account no longer matches its saved identity")
        return
      }
      let path = try accountOnboarder.preserveAccount(from: activeHome.path)
      managedPath = path
      let preservedProbe = try await accountProbe.probe(codexHomePath: path)
      guard preservedProbe.identityHash == expectedIdentity else {
        try? accountOnboarder.discardManagedAccount(at: path)
        activity = .failure(message: "SwitchGPT could not verify the preserved account")
        return
      }

      let previous = accounts[index]
      accounts[index] = AccountRecord(
        id: previous.id,
        displayName: previous.displayName,
        email: preservedProbe.email ?? previous.email,
        detail: previous.detail,
        planName: preservedProbe.planName,
        symbolName: previous.symbolName,
        accent: previous.accent,
        usage: preservedProbe.usage,
        source: .codexHome(path: path),
        identityHash: previous.identityHash
      )
      lastRefreshedAt = Date()
      if persistState() {
        activity = .success(message: "Current account secured for switching")
      } else {
        try? accountOnboarder.discardManagedAccount(at: path)
      }
    } catch {
      if let managedPath { try? accountOnboarder.discardManagedAccount(at: managedPath) }
      activity = .failure(message: "SwitchGPT could not secure the current account")
    }
  }

  /// Reconciles the UI's current marker with the identity actually active in ChatGPT. Adding an
  /// isolated account must never imply that the desktop client switched to that account.
  public func reconcileCurrentAccountWithDesktop() async {
    guard !activity.isBusy else { return }
    let activeHome = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .path

    do {
      let activeProbe = try await accountProbe.probe(codexHomePath: activeHome)
      guard let index = accounts.firstIndex(where: { $0.identityHash == activeProbe.identityHash })
      else { return }

      let previous = accounts[index]
      accounts[index] = AccountRecord(
        id: previous.id,
        displayName: previous.displayName,
        email: activeProbe.email ?? previous.email,
        detail: previous.detail,
        planName: activeProbe.planName,
        symbolName: previous.symbolName,
        accent: previous.accent,
        usage: activeProbe.usage,
        source: previous.source,
        identityHash: previous.identityHash
      )
      currentAccountID = previous.id
      lastRefreshedAt = Date()
      _ = persistState()
    } catch {
      NSLog(
        "[SwitchGPT/account] active account reconciliation failed: %@",
        String(describing: error)
      )
    }
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
      !isCurrent(accountID)
    else { return }

    guard case .mock = accounts[index].source else { return }
    let removed = accounts.remove(at: index)
    if persistState() {
      activity = .success(message: "Removed mock account: " + removed.displayName)
    }
  }

  public func removeAccount(_ accountID: AccountID) {
    guard !activity.isBusy,
      accounts.count > 1,
      let index = accounts.firstIndex(where: { $0.id == accountID })
    else { return }
    guard !isCurrent(accountID) else { return }

    let previousAccounts = accounts
    let previousCurrentAccountID = currentAccountID
    let removed = accounts.remove(at: index)
    guard persistState() else {
      accounts = previousAccounts
      currentAccountID = previousCurrentAccountID
      return
    }
    if case .codexHome(let path) = removed.source {
      try? accountOnboarder.discardManagedAccount(at: path)
    }
    activity = .success(message: "Removed account: " + removed.accountLabel)
  }

  public func selectAccount(_ accountID: AccountID) {
    guard !activity.isBusy, accounts.contains(where: { $0.id == accountID }) else { return }
    currentAccountID = accountID
    _ = persistState()
  }

  public func refresh(reportsActivity: Bool = true) async {
    guard !activity.isBusy, !accounts.isEmpty else { return }

    let previousActivity = activity
    if reportsActivity {
      activity = .refreshing
    }
    do {
      let snapshotsByAccount = try await quotaReader.fetchSnapshots(for: accounts)
      accounts = accounts.map { account in
        var updated = account
        if let snapshot = snapshotsByAccount[account.id] {
          updated = AccountRecord(
            id: account.id,
            displayName: account.displayName,
            email: snapshot.email ?? account.email,
            detail: account.detail,
            planName: snapshot.planName,
            symbolName: account.symbolName,
            accent: account.accent,
            usage: snapshot.usage,
            source: account.source,
            identityHash: account.identityHash
          )
        }
        return updated
      }
      lastRefreshedAt = Date()
      if persistState() {
        if reportsActivity {
          activity = .success(message: "Usage refreshed")
        }
      } else if !reportsActivity {
        activity = previousActivity
      }
    } catch {
      if reportsActivity {
        activity = .failure(message: "Could not refresh usage")
      } else {
        activity = previousActivity
        NSLog("[SwitchGPT/quota] background refresh failed: %@", String(describing: error))
      }
    }
  }

  /// Refreshes one target immediately before switching so the confirmation always uses current
  /// quota and membership data without making unrelated accounts a point of failure.
  @discardableResult
  public func refreshAccount(_ accountID: AccountID) async -> Bool {
    guard !activity.isBusy,
      let account = accounts.first(where: { $0.id == accountID })
    else { return false }

    activity = .refreshing
    do {
      let snapshots = try await quotaReader.fetchSnapshots(for: [account])
      guard let snapshot = snapshots[accountID],
        let index = accounts.firstIndex(where: { $0.id == accountID })
      else {
        activity = .failure(message: "Could not refresh the selected account")
        return false
      }

      let previous = accounts[index]
      accounts[index] = AccountRecord(
        id: previous.id,
        displayName: previous.displayName,
        email: snapshot.email ?? previous.email,
        detail: previous.detail,
        planName: snapshot.planName,
        symbolName: previous.symbolName,
        accent: previous.accent,
        usage: snapshot.usage,
        source: previous.source,
        identityHash: previous.identityHash
      )
      lastRefreshedAt = Date()
      if persistState() {
        activity = .success(message: "Selected account refreshed")
        return true
      }
      return false
    } catch {
      activity = .failure(message: "Could not refresh the selected account")
      return false
    }
  }

  public func refreshIfStale(
    maxAge: TimeInterval,
    now: Date = Date(),
    reportsActivity: Bool = true
  ) async {
    guard maxAge >= 0 else { return }
    guard !accounts.isEmpty else { return }
    guard let lastRefreshedAt else {
      await refresh(reportsActivity: reportsActivity)
      return
    }
    if now.timeIntervalSince(lastRefreshedAt) >= maxAge {
      await refresh(reportsActivity: reportsActivity)
    }
  }

  public var needsAccountMetadataRefresh: Bool {
    accounts.contains { account in
      guard case .codexHome = account.source else { return false }
      return account.email == nil || account.planName == "ChatGPT" || account.planName == "Unknown"
        || !account.usage.creditsWereLoaded
    }
  }

  public func simulateSwitch(to targetID: AccountID) async {
    guard let target = accounts.first(where: { $0.id == targetID }), !isCurrent(target.id)
    else {
      return
    }
    guard !activity.isBusy else { return }

    activity = .simulating(targetName: target.accountLabel)
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

  public func beginRealSwitch(to targetID: AccountID) -> Bool {
    guard !activity.isBusy,
      let target = accounts.first(where: { $0.id == targetID }),
      case .codexHome = target.source
    else { return false }
    activity = .switching(targetName: target.accountLabel)
    return true
  }

  public func completeRealSwitch(to targetID: AccountID, receiptRecorded: Bool = true) {
    guard let target = accounts.first(where: { $0.id == targetID }) else {
      activity = .failure(message: "The switched account is no longer configured")
      return
    }
    currentAccountID = target.id
    if persistState() {
      activity = .success(
        message: "ChatGPT switched to " + target.accountLabel
          + (receiptRecorded
            ? ". A private metadata-only verification receipt was saved."
            : ". The local verification receipt could not be saved.")
      )
    }
  }

  public func failRealSwitch(message: String) {
    activity = .failure(message: message)
  }

  public func resetActivity() {
    guard !activity.isBusy else { return }
    activity = .ready
  }

  private func persistState() -> Bool {
    guard !accounts.isEmpty else { return true }
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
      state.accounts.allSatisfy({ account in
        switch account.source {
        case .mock:
          return account.identityHash == nil
        case .codexHome(let path):
          return path.hasPrefix("/") && Self.isValidIdentityHash(account.identityHash)
        }
      })
    else { return false }

    if let currentAccountID = state.currentAccountID {
      guard state.accounts.contains(where: { $0.id == currentAccountID }) else { return false }
    }

    return true
  }

  private static func isValidIdentityHash(_ value: String?) -> Bool {
    guard let value, value.count == 12 else { return false }
    return value.allSatisfy { $0.isHexDigit }
  }

  private func isCurrent(_ accountID: AccountID) -> Bool {
    currentAccountID.map { $0 == accountID } ?? false
  }

  private static func isUntouchedDemoCatalog(_ accounts: [AccountRecord]) -> Bool {
    guard accounts.count == 2 else { return false }
    return Set(accounts.map(\.id)) == Set([AccountID("personal"), AccountID("work")])
      && accounts.allSatisfy { account in
        if case .mock = account.source { return true }
        return false
      }
  }
}
