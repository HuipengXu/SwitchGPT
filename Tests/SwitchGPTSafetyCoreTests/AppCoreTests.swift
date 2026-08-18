import XCTest

@testable import SwitchGPTAppCore

final class AppCoreTests: XCTestCase {
  func testRealSwitchReceiptStorePersistsMetadataOnlyEvidenceWithoutOverwrite() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-receipt-store-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let store = RealSwitchReceiptStore(
      directoryURL: root.appendingPathComponent("SwitchReceipts", isDirectory: true)
    )
    let id = UUID()
    let receipt = RealSwitchReceipt(
      id: id,
      sourceIdentityHash: "012345abcdef",
      targetIdentityHash: "fedcba543210",
      outcome: .rolledBack,
      finalIdentityHash: "012345abcdef",
      targetLaunchAttempts: 1,
      rollbackLaunchAttempts: 1,
      targetWasInstalled: true,
      failureReason: .targetIdentityMismatch,
      transactionCreatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      recordedAt: Date(timeIntervalSince1970: 1_700_000_010)
    )

    let receiptURL = try store.save(receipt)

    XCTAssertEqual(try store.load(id: id), receipt)
    let attributes = try FileManager.default.attributesOfItem(atPath: receiptURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    let persistedText = try String(contentsOf: receiptURL, encoding: .utf8)
    XCTAssertFalse(persistedText.contains("access_token"))
    XCTAssertFalse(persistedText.contains("refresh_token"))
    XCTAssertFalse(persistedText.contains("auth.json"))
    XCTAssertThrowsError(try store.save(receipt)) { error in
      XCTAssertEqual(error as? RealSwitchReceiptStoreError, .receiptAlreadyExists)
    }
  }

  func testRealSwitchReceiptStoreRejectsInvalidIdentityMetadata() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-invalid-receipt-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = RealSwitchReceiptStore(directoryURL: root)
    let receipt = RealSwitchReceipt(
      id: UUID(),
      sourceIdentityHash: "not-a-hash",
      targetIdentityHash: "fedcba543210",
      outcome: .committed,
      finalIdentityHash: "fedcba543210",
      targetLaunchAttempts: 1,
      rollbackLaunchAttempts: 0,
      targetWasInstalled: true,
      failureReason: nil,
      transactionCreatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      recordedAt: Date(timeIntervalSince1970: 1_700_000_001)
    )

    XCTAssertThrowsError(try store.save(receipt)) { error in
      XCTAssertEqual(error as? RealSwitchReceiptStoreError, .invalidReceipt)
    }
  }

  func testMockReaderReturnsUsageForEveryAccount() async throws {
    let accounts = MockAccountCatalog.accounts(now: Date(timeIntervalSince1970: 1_700_000_000))
    let usage = try await MockQuotaReader().fetchUsage(for: accounts)

    XCTAssertEqual(usage.count, accounts.count)
    XCTAssertNotNil(usage[AccountID("personal")])
    XCTAssertNil(usage[AccountID("personal")]?.fiveHour)
    XCTAssertNil(usage[AccountID("work")]?.fiveHour)
  }

  @MainActor
  func testSimulationChangesOnlySelectedInMemoryAccount() async {
    let store = SwitchGPTAppStore(now: Date(timeIntervalSince1970: 1_700_000_000))
    let originalID = store.currentAccountID

    await store.simulateSwitch(to: AccountID("work"))

    XCTAssertEqual(originalID, AccountID("personal"))
    XCTAssertEqual(store.currentAccountID, AccountID("work"))
    XCTAssertEqual(store.activity.message, "Simulation complete — no desktop account changed")
  }

  @MainActor
  func testRefreshKeepsCurrentIdentity() async {
    let store = SwitchGPTAppStore(now: Date(timeIntervalSince1970: 1_700_000_000))
    await store.refresh()

    XCTAssertEqual(store.currentAccountID, AccountID("personal"))
    XCTAssertNotNil(store.lastRefreshedAt)
    XCTAssertEqual(store.accounts.count, 2)
    XCTAssertFalse(store.activity.isFailure)
  }

  @MainActor
  func testTargetedRefreshUpdatesOnlySelectedAccountBeforeSwitching() async {
    let refreshedUsage = AccountUsage(
      weekly: UsageWindow(usedPercent: 88, resetAt: Date(timeIntervalSince1970: 1_900_000_000))
    )
    let store = SwitchGPTAppStore(
      quotaReader: FixedSnapshotQuotaReader(
        snapshot: AccountQuotaSnapshot(planName: "Free", usage: refreshedUsage)
      ),
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let originalCurrentID = store.currentAccountID
    let untouchedUsage = store.accounts[0].usage

    let refreshed = await store.refreshAccount(AccountID("work"))

    XCTAssertTrue(refreshed)
    XCTAssertEqual(store.currentAccountID, originalCurrentID)
    XCTAssertEqual(store.accounts.first { $0.id == AccountID("personal") }?.usage, untouchedUsage)
    XCTAssertEqual(store.accounts.first { $0.id == AccountID("work") }?.usage, refreshedUsage)
    XCTAssertEqual(store.accounts.first { $0.id == AccountID("work") }?.planName, "Free")
  }

  @MainActor
  func testRefreshIfStaleSkipsFreshDataAndRefreshesExpiredData() async {
    let reader = CountingQuotaReader()
    let store = SwitchGPTAppStore(quotaReader: reader)
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    await store.refreshIfStale(maxAge: 10, now: base)
    var refreshCount = await reader.count
    XCTAssertEqual(refreshCount, 1)

    guard let refreshed = store.lastRefreshedAt else {
      XCTFail("Expected refresh timestamp")
      return
    }
    await store.refreshIfStale(maxAge: 10, now: refreshed.addingTimeInterval(9))
    refreshCount = await reader.count
    XCTAssertEqual(refreshCount, 1)

    await store.refreshIfStale(maxAge: 10, now: refreshed.addingTimeInterval(10))
    refreshCount = await reader.count
    XCTAssertEqual(refreshCount, 2)
  }

  @MainActor
  func testStoreSupportsMoreThanTwoAccounts() async {
    let store = SwitchGPTAppStore(now: Date(timeIntervalSince1970: 1_700_000_000))
    let addedID = store.addMockAccount(displayName: "Research", detail: "Reading workspace")

    XCTAssertNotNil(addedID)
    XCTAssertEqual(store.accounts.count, 3)

    guard let addedID else {
      return
    }

    await store.simulateSwitch(to: addedID)
    XCTAssertEqual(store.currentAccountID, addedID)

    store.removeMockAccount(AccountID("personal"))
    XCTAssertEqual(store.accounts.count, 2)
    XCTAssertEqual(store.currentAccountID, addedID)
  }

  func testRateLimitDecoderSupportsSecondaryWindow() throws {
    let payload = """
      {
        "rateLimitsByLimitId": {
          "codex": {
            "primary": {"usedPercent": 37, "resetsAt": 1787059702},
            "secondary": {"usedPercent": 12, "resetsAt": 1787000000000}
          }
        }
      }
      """.data(using: .utf8)!

    let usage = try CodexRateLimitDecoder.decodeUsage(from: payload)

    XCTAssertEqual(usage.weekly.usedPercent, 37)
    XCTAssertEqual(usage.fiveHour?.usedPercent, 12)
    XCTAssertNil(usage.credits)
    XCTAssertTrue(usage.creditsWereLoaded)
    XCTAssertEqual(usage.weekly.resetAt.timeIntervalSince1970, 1_787_059_702, accuracy: 0.1)
    XCTAssertEqual(usage.fiveHour?.resetAt.timeIntervalSince1970 ?? 0, 1_787_000_000, accuracy: 0.1)
  }

  func testRateLimitDecoderPreservesCreditsPointsAndConvertsToUSD() throws {
    let payload = """
      {
        "rateLimitsByLimitId": {
          "codex": {
            "primary": {"usedPercent": 100, "resetsAt": 1787059702},
            "credits": {
              "hasCredits": true,
              "unlimited": false,
              "balance": "800.0000000000"
            }
          }
        }
      }
      """.data(using: .utf8)!

    let usage = try CodexRateLimitDecoder.decodeUsage(from: payload)

    XCTAssertEqual(usage.weekly.usedPercent, 100)
    XCTAssertEqual(usage.credits?.hasCredits, true)
    XCTAssertEqual(usage.credits?.unlimited, false)
    XCTAssertEqual(usage.credits?.points, Decimal(800))
    XCTAssertEqual(usage.credits?.usdBalance, Decimal(32))
    XCTAssertTrue(usage.creditsWereLoaded)
  }

  func testRateLimitDecoderSupportsUnlimitedCreditsWithoutBalance() throws {
    let payload = """
      {
        "rateLimits": {
          "primary": {"usedPercent": 100, "resetsAt": 1787059702},
          "credits": {
            "hasCredits": true,
            "unlimited": true,
            "balance": null
          }
        }
      }
      """.data(using: .utf8)!

    let usage = try CodexRateLimitDecoder.decodeUsage(from: payload)

    XCTAssertEqual(usage.credits, CreditBalance(hasCredits: true, unlimited: true))
    XCTAssertEqual(usage.credits?.isDisplayable, true)
    XCTAssertTrue(usage.creditsWereLoaded)
  }

  func testCreditBalanceDecodesPreviouslyPersistedBalanceAsPoints() throws {
    let payload = """
      {
        "hasCredits": true,
        "unlimited": false,
        "balance": 800
      }
      """.data(using: .utf8)!

    let credits = try JSONDecoder().decode(CreditBalance.self, from: payload)
    let encoded = try JSONEncoder().encode(credits)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(credits.points, Decimal(800))
    XCTAssertEqual(credits.usdBalance, Decimal(32))
    XCTAssertNotNil(object["points"])
    XCTAssertNil(object["balance"])
  }

  func testAccountUsageDecodesLegacyStateWithoutCredits() throws {
    let original = AccountUsage(
      weekly: UsageWindow(usedPercent: 37, resetAt: Date(timeIntervalSince1970: 1_787_059_702))
    )
    let encoded = try JSONEncoder().encode(original)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "credits")
    object.removeValue(forKey: "creditsWereLoaded")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(AccountUsage.self, from: legacyData)

    XCTAssertEqual(decoded.weekly, original.weekly)
    XCTAssertNil(decoded.credits)
    XCTAssertFalse(decoded.creditsWereLoaded)
  }

  func testRateLimitDecoderRejectsMissingPrimaryWindow() {
    let payload = "{\"rateLimits\": {\"secondary\": null}}".data(using: .utf8)!

    XCTAssertThrowsError(try CodexRateLimitDecoder.decodeUsage(from: payload)) { error in
      XCTAssertEqual(error as? QuotaReadingError, .missingRateLimit)
    }
  }

  func testAccountDecoderPreservesFreeMembership() throws {
    let payload = """
      {
        "account": {
          "type": "chatgpt",
          "email": "member@example.com",
          "planType": "free"
        },
        "requiresOpenaiAuth": true
      }
      """.data(using: .utf8)!

    let metadata = try CodexAccountDecoder.decode(from: payload)

    XCTAssertEqual(metadata.identityHash.count, 12)
    XCTAssertEqual(metadata.email, "member@example.com")
    XCTAssertEqual(metadata.planName, "Free")
  }

  func testMembershipNamesCoverCurrentProtocolValues() {
    XCTAssertEqual(ChatGPTMembership.displayName(for: "plus"), "Plus")
    XCTAssertEqual(ChatGPTMembership.displayName(for: "prolite"), "Pro Lite")
    XCTAssertEqual(
      ChatGPTMembership.displayName(for: "self_serve_business_usage_based"),
      "Business"
    )
    XCTAssertEqual(ChatGPTMembership.displayName(for: "enterprise"), "Enterprise")
    XCTAssertEqual(ChatGPTMembership.displayName(for: nil), "Unknown")
  }

  func testLongEmailUsesMiddleTruncationWhilePreservingDomain() {
    let account = AccountRecord(
      id: AccountID("long-email"),
      displayName: "Fallback",
      email: "a-very-long-personal-address@example.com",
      detail: "",
      planName: "Plus",
      symbolName: "person.crop.circle",
      accent: .orange,
      usage: AccountUsage(weekly: UsageWindow(usedPercent: 0, resetAt: Date()))
    )

    let compact = account.compactAccountLabel(maximumLength: 30)

    XCTAssertLessThanOrEqual(compact.count, 30)
    XCTAssertTrue(compact.contains("…"))
    XCTAssertTrue(compact.hasSuffix("@example.com"))
  }

  func testPreviewStateFileStorePersistsReadOnlyMetadataWithoutCredentials() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-preview-state-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let fileURL = root.appendingPathComponent("preview-state.json")
    let persistence = PreviewStateFileStore(fileURL: fileURL)
    let accounts = MockAccountCatalog.accounts(now: Date(timeIntervalSince1970: 1_700_000_000))
    let state = PreviewState(
      accounts: accounts,
      currentAccountID: AccountID("work"),
      lastRefreshedAt: Date(timeIntervalSince1970: 1_700_000_123)
    )

    try persistence.save(state)

    XCTAssertEqual(try persistence.load(), state)
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

    let realAccount = AccountRecord(
      id: AccountID("real"),
      displayName: "Real",
      email: "real@example.com",
      detail: "Read-only quota",
      planName: "ChatGPT Plus",
      symbolName: "person.crop.circle",
      accent: .orange,
      usage: accounts[0].usage,
      source: .codexHome(path: "/private/outside-repository"),
      identityHash: "a1b2c3d4e5f6"
    )
    let readOnlyState = PreviewState(
      accounts: [realAccount],
      currentAccountID: realAccount.id
    )

    try persistence.save(readOnlyState)
    XCTAssertEqual(try persistence.load(), readOnlyState)
    let persistedText = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertFalse(persistedText.contains("access_token"))
    XCTAssertFalse(persistedText.contains("refresh_token"))

    let invalidAccount = AccountRecord(
      id: AccountID("invalid"),
      displayName: "Invalid",
      detail: "Invalid pin",
      planName: "ChatGPT",
      symbolName: "person.crop.circle",
      accent: .blue,
      usage: accounts[0].usage,
      source: .codexHome(path: "/private/outside-repository"),
      identityHash: "redacted"
    )
    let unsafeState = PreviewState(accounts: [invalidAccount], currentAccountID: invalidAccount.id)

    XCTAssertThrowsError(try persistence.save(unsafeState)) { error in
      XCTAssertEqual(error as? PreviewStatePersistenceError, .unsupportedAccountSource)
    }
  }

  @MainActor
  func testStoreAddsAndRestoresReadOnlyAccountFromPinnedProbe() async {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-readonly-store-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let persistence = PreviewStateFileStore(fileURL: root.appendingPathComponent("state.json"))
    let usage = AccountUsage(
      weekly: UsageWindow(usedPercent: 42, resetAt: Date(timeIntervalSince1970: 1_800_000_000)),
      fiveHour: UsageWindow(usedPercent: 7, resetAt: Date(timeIntervalSince1970: 1_790_000_000))
    )
    let store = SwitchGPTAppStore(
      accountProbe: StubAccountProbe(
        result: .success(
          ReadOnlyAccountProbe(identityHash: "012345abcdef", usage: usage)
        )),
      persistence: persistence
    )

    let addedID = await store.addReadOnlyAccount(
      displayName: "Primary",
      detail: "Personal",
      codexHomePath: "/private/account-a"
    )

    XCTAssertNotNil(addedID)
    XCTAssertEqual(store.currentAccountID, AccountID("personal"))
    let addedAccount = store.accounts.first { $0.id == addedID }
    XCTAssertEqual(addedAccount?.usage, usage)
    XCTAssertEqual(addedAccount?.identityHash, "012345abcdef")
    XCTAssertEqual(addedAccount?.planName, "Unknown")
    XCTAssertEqual(store.accounts.count, 3)

    let restored = SwitchGPTAppStore(persistence: persistence)
    XCTAssertEqual(restored.currentAccountID, AccountID("personal"))
    let restoredAccount = restored.accounts.first { $0.id == addedID }
    XCTAssertEqual(restoredAccount?.source, .codexHome(path: "/private/account-a"))
    XCTAssertEqual(restoredAccount?.identityHash, "012345abcdef")
  }

  @MainActor
  func testBootstrapReplacesOnlyUntouchedDemoCatalogWithCurrentRealAccount() async {
    let usage = AccountUsage(
      weekly: UsageWindow(usedPercent: 33, resetAt: Date(timeIntervalSince1970: 1_800_000_000))
    )
    let store = SwitchGPTAppStore(
      accountProbe: StubAccountProbe(
        result: .success(
          ReadOnlyAccountProbe(identityHash: "012345abcdef", usage: usage)
        ))
    )

    await store.bootstrapCurrentAccountIfNeeded()

    XCTAssertEqual(store.accounts.count, 1)
    XCTAssertEqual(store.currentAccount?.displayName, "Current account")
    XCTAssertEqual(store.currentAccount?.usage, usage)
    XCTAssertEqual(store.currentAccount?.identityHash, "012345abcdef")
    XCTAssertEqual(
      store.currentAccount?.source,
      .codexHome(
        path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
    )
  }

  @MainActor
  func testBootstrapPreservesUserCustomizedCatalog() async {
    let probe = StubAccountProbe(
      result: .success(
        ReadOnlyAccountProbe(
          identityHash: "012345abcdef",
          usage: AccountUsage(weekly: UsageWindow(usedPercent: 1, resetAt: Date()))
        )
      ))
    let store = SwitchGPTAppStore(accountProbe: probe)
    _ = store.addMockAccount(displayName: "Research", detail: "Custom")

    await store.bootstrapCurrentAccountIfNeeded()

    XCTAssertEqual(store.accounts.count, 3)
    XCTAssertEqual(store.currentAccountID, AccountID("personal"))
  }

  @MainActor
  func testStorePreservesMutableActiveAccountIntoManagedStorage() async {
    let activePath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true).path
    let managedPath = "/private/managed-active"
    let onboarder = StubManagedAccountOnboarder(
      path: "/private/new-login",
      preservedPath: managedPath
    )
    let probe = StubAccountProbe(
      result: .success(
        ReadOnlyAccountProbe(
          identityHash: "012345abcdef",
          usage: AccountUsage(weekly: UsageWindow(usedPercent: 12, resetAt: Date()))
        )
      ))
    let persistence = InMemoryPreviewStateStore(
      state: PreviewState(
        accounts: [
          AccountRecord(
            id: AccountID("active"),
            displayName: "Current account",
            detail: "Active ChatGPT account",
            planName: "ChatGPT",
            symbolName: "person.crop.circle",
            accent: .orange,
            usage: AccountUsage(weekly: UsageWindow(usedPercent: 20, resetAt: Date())),
            source: .codexHome(path: activePath),
            identityHash: "012345abcdef"
          )
        ],
        currentAccountID: AccountID("active")
      ))
    let store = SwitchGPTAppStore(
      accountProbe: probe,
      accountOnboarder: onboarder,
      persistence: persistence
    )

    await store.preserveActiveAccountForSwitchingIfNeeded()

    XCTAssertEqual(store.currentAccount?.source, .codexHome(path: managedPath))
    XCTAssertEqual(onboarder.preservedSourcePaths, [activePath])
    XCTAssertFalse(store.activity.isFailure)
  }

  @MainActor
  func testStoreRejectsDuplicateReadOnlyIdentity() async {
    let probe = StubAccountProbe(
      result: .success(
        ReadOnlyAccountProbe(
          identityHash: "012345abcdef",
          usage: AccountUsage(weekly: UsageWindow(usedPercent: 1, resetAt: Date()))
        )
      ))
    let store = SwitchGPTAppStore(accountProbe: probe)

    let first = await store.addReadOnlyAccount(
      displayName: "One", detail: "", codexHomePath: "/private/one"
    )
    let second = await store.addReadOnlyAccount(
      displayName: "Two", detail: "", codexHomePath: "/private/two"
    )
    XCTAssertNotNil(first)
    XCTAssertNil(second)
    XCTAssertEqual(store.accounts.count, 3)
    XCTAssertTrue(store.activity.isFailure)
  }

  @MainActor
  func testManagedSignInAddsAccountWithoutUserSuppliedPath() async {
    let onboarder = StubManagedAccountOnboarder(path: "/private/managed-account")
    let usage = AccountUsage(
      weekly: UsageWindow(usedPercent: 22, resetAt: Date(timeIntervalSince1970: 1_800_000_000))
    )
    let store = SwitchGPTAppStore(
      accountProbe: StubAccountProbe(
        result: .success(
          ReadOnlyAccountProbe(
            identityHash: "abcdef012345",
            email: "free@example.com",
            planName: "Free",
            usage: usage
          )
        )),
      accountOnboarder: onboarder
    )

    let accountID = await store.signInAccount()

    XCTAssertNotNil(accountID)
    XCTAssertEqual(store.currentAccountID, AccountID("personal"))
    let addedAccount = store.accounts.first { $0.id == accountID }
    XCTAssertEqual(addedAccount?.accountLabel, "free@example.com")
    XCTAssertEqual(addedAccount?.email, "free@example.com")
    XCTAssertEqual(addedAccount?.detail, "")
    XCTAssertEqual(addedAccount?.source, .codexHome(path: "/private/managed-account"))
    XCTAssertEqual(addedAccount?.usage, usage)
    XCTAssertEqual(addedAccount?.planName, "Free")
    XCTAssertTrue(onboarder.discardedPaths.isEmpty)
    XCTAssertEqual(store.accountOnboardingActivity, .idle)
    XCTAssertFalse(store.activity.isBusy)
  }

  @MainActor
  func testManagedSignInDoesNotBlockUsageRefreshAndCanBeCancelled() async {
    let quotaReader = CountingQuotaReader()
    let store = SwitchGPTAppStore(
      quotaReader: quotaReader,
      accountOnboarder: SlowManagedAccountOnboarder()
    )
    let signInTask = Task { await store.signInAccount() }

    while !store.accountOnboardingActivity.isInProgress {
      await Task.yield()
    }

    XCTAssertFalse(store.activity.isBusy)
    await store.refresh()

    let refreshCount = await quotaReader.count
    XCTAssertEqual(refreshCount, 1)
    XCTAssertTrue(store.accountOnboardingActivity.isInProgress)
    XCTAssertFalse(store.activity.isBusy)

    signInTask.cancel()
    let result = await signInTask.value
    XCTAssertNil(result)
    XCTAssertEqual(store.accountOnboardingActivity, .idle)
  }

  @MainActor
  func testReconcileCurrentAccountUsesActiveDesktopIdentity() async {
    let usage = AccountUsage(
      weekly: UsageWindow(usedPercent: 9, resetAt: Date(timeIntervalSince1970: 1_800_000_000))
    )
    let accounts = [
      AccountRecord(
        id: AccountID("one"),
        displayName: "One",
        detail: "Saved ChatGPT account",
        planName: "Plus",
        symbolName: "person.crop.circle",
        accent: .orange,
        usage: usage,
        source: .codexHome(path: "/private/one"),
        identityHash: "111111111111"
      ),
      AccountRecord(
        id: AccountID("two"),
        displayName: "Two",
        detail: "Saved ChatGPT account",
        planName: "ChatGPT",
        symbolName: "person.crop.circle",
        accent: .blue,
        usage: usage,
        source: .codexHome(path: "/private/two"),
        identityHash: "222222222222"
      ),
    ]
    let persistence = InMemoryPreviewStateStore(
      state: PreviewState(accounts: accounts, currentAccountID: AccountID("one"))
    )
    let store = SwitchGPTAppStore(
      accountProbe: StubAccountProbe(
        result: .success(
          ReadOnlyAccountProbe(
            identityHash: "222222222222",
            email: "two@example.com",
            planName: "Free",
            usage: usage
          )
        )
      ),
      persistence: persistence
    )

    await store.reconcileCurrentAccountWithDesktop()

    XCTAssertEqual(store.currentAccountID, AccountID("two"))
    XCTAssertEqual(store.currentAccount?.accountLabel, "two@example.com")
    XCTAssertEqual(store.currentAccount?.planName, "Free")
  }

  @MainActor
  func testManagedSignInDiscardsDuplicateAccountStorage() async {
    let onboarder = StubManagedAccountOnboarder(path: "/private/managed-duplicate")
    let probe = StubAccountProbe(
      result: .success(
        ReadOnlyAccountProbe(
          identityHash: "abcdef012345",
          usage: AccountUsage(weekly: UsageWindow(usedPercent: 1, resetAt: Date()))
        )
      ))
    let store = SwitchGPTAppStore(accountProbe: probe, accountOnboarder: onboarder)
    _ = await store.addReadOnlyAccount(
      displayName: "Existing",
      detail: "",
      codexHomePath: "/private/existing"
    )

    let duplicate = await store.signInAccount()

    XCTAssertNil(duplicate)
    XCTAssertEqual(onboarder.discardedPaths, ["/private/managed-duplicate"])
    XCTAssertFalse(store.activity.isFailure)
    XCTAssertEqual(
      store.accountOnboardingActivity,
      .failure(message: "This account is already configured")
    )
  }

  func testPreviewStateFileStoreRejectsBroadFilePermissions() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-preview-state-permissions-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let fileURL = root.appendingPathComponent("preview-state.json")
    let persistence = PreviewStateFileStore(fileURL: fileURL)
    let accounts = MockAccountCatalog.accounts()
    try persistence.save(
      PreviewState(accounts: accounts, currentAccountID: accounts[0].id)
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

    XCTAssertThrowsError(try persistence.load()) { error in
      XCTAssertEqual(error as? PreviewStatePersistenceError, .insecureFile)
    }
  }

  func testPreviewStateFileStoreRejectsSymbolicLink() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-preview-state-symlink-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let targetURL = root.appendingPathComponent("target.json")
    let linkURL = root.appendingPathComponent("preview-state.json")
    let targetStore = PreviewStateFileStore(fileURL: targetURL)
    let accounts = MockAccountCatalog.accounts()
    try targetStore.save(PreviewState(accounts: accounts, currentAccountID: accounts[0].id))
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

    XCTAssertThrowsError(try PreviewStateFileStore(fileURL: linkURL).load()) { error in
      XCTAssertEqual(error as? PreviewStatePersistenceError, .invalidFile)
    }
  }

  func testPreviewStateFileStoreRejectsCorruptedJSON() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-preview-state-corrupt-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let fileURL = root.appendingPathComponent("preview-state.json")
    let persistence = PreviewStateFileStore(fileURL: fileURL)
    let accounts = MockAccountCatalog.accounts()
    try persistence.save(PreviewState(accounts: accounts, currentAccountID: accounts[0].id))
    try Data("{not-json".utf8).write(to: fileURL)

    XCTAssertThrowsError(try persistence.load()) { error in
      XCTAssertEqual(error as? PreviewStatePersistenceError, .invalidFile)
    }
  }

  @MainActor
  func testStoreRestoresPersistedMockAccountsAndSelection() async {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-store-state-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let persistence = PreviewStateFileStore(
      fileURL: root.appendingPathComponent("preview-state.json")
    )
    let firstStore = SwitchGPTAppStore(
      now: Date(timeIntervalSince1970: 1_700_000_000),
      persistence: persistence
    )
    let addedID = firstStore.addMockAccount(
      displayName: "Research",
      detail: "Reading workspace"
    )
    XCTAssertNotNil(addedID)

    if let addedID {
      await firstStore.simulateSwitch(to: addedID)
    }

    let restoredStore = SwitchGPTAppStore(
      now: Date(timeIntervalSince1970: 1_700_000_000),
      persistence: persistence
    )
    XCTAssertEqual(restoredStore.accounts.count, 3)
    XCTAssertEqual(restoredStore.currentAccountID, addedID)
    XCTAssertNil(restoredStore.lastPersistenceError)
  }
}

private struct StubAccountProbe: ReadOnlyAccountProbing {
  let result: Result<ReadOnlyAccountProbe, QuotaReadingError>

  func probe(codexHomePath: String) async throws -> ReadOnlyAccountProbe {
    try result.get()
  }
}

private actor CountingQuotaReader: QuotaReading {
  private(set) var count = 0

  func fetchSnapshots(for accounts: [AccountRecord]) async throws
    -> [AccountID: AccountQuotaSnapshot]
  {
    count += 1
    return Dictionary(
      uniqueKeysWithValues: accounts.map {
        ($0.id, AccountQuotaSnapshot(planName: $0.planName, usage: $0.usage))
      })
  }
}

private struct FixedSnapshotQuotaReader: QuotaReading {
  let snapshot: AccountQuotaSnapshot

  func fetchSnapshots(for accounts: [AccountRecord]) async throws
    -> [AccountID: AccountQuotaSnapshot]
  {
    Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, snapshot) })
  }
}

private final class StubManagedAccountOnboarder: ManagedAccountOnboarding, @unchecked Sendable {
  let path: String
  let preservedPath: String
  private let lock = NSLock()
  private var storedDiscardedPaths: [String] = []
  private var storedPreservedSourcePaths: [String] = []

  var discardedPaths: [String] {
    lock.withLock { storedDiscardedPaths }
  }

  var preservedSourcePaths: [String] {
    lock.withLock { storedPreservedSourcePaths }
  }

  init(path: String, preservedPath: String? = nil) {
    self.path = path
    self.preservedPath = preservedPath ?? path
  }

  func signIn() async throws -> String { path }

  func preserveAccount(from codexHomePath: String) throws -> String {
    lock.withLock { storedPreservedSourcePaths.append(codexHomePath) }
    return preservedPath
  }

  func discardManagedAccount(at path: String) throws {
    lock.withLock { storedDiscardedPaths.append(path) }
  }
}

private struct SlowManagedAccountOnboarder: ManagedAccountOnboarding {
  func signIn() async throws -> String {
    try await Task.sleep(for: .seconds(30))
    return "/private/slow-managed-account"
  }

  func preserveAccount(from codexHomePath: String) throws -> String {
    codexHomePath
  }

  func discardManagedAccount(at path: String) throws {}
}

private final class InMemoryPreviewStateStore: PreviewStatePersisting, @unchecked Sendable {
  private let lock = NSLock()
  private var state: PreviewState?

  init(state: PreviewState?) {
    self.state = state
  }

  func load() throws -> PreviewState? {
    lock.withLock { state }
  }

  func save(_ state: PreviewState) throws {
    lock.withLock { self.state = state }
  }
}
