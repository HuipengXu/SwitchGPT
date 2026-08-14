import XCTest
@testable import SwitchGPTAppCore

final class AppCoreTests: XCTestCase {
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
    XCTAssertEqual(usage.weekly.resetAt.timeIntervalSince1970, 1_787_059_702, accuracy: 0.1)
    XCTAssertEqual(usage.fiveHour?.resetAt.timeIntervalSince1970 ?? 0, 1_787_000_000, accuracy: 0.1)
  }

  func testRateLimitDecoderRejectsMissingPrimaryWindow() {
    let payload = "{\"rateLimits\": {\"secondary\": null}}".data(using: .utf8)!

    XCTAssertThrowsError(try CodexRateLimitDecoder.decodeUsage(from: payload)) { error in
      XCTAssertEqual(error as? QuotaReadingError, .missingRateLimit)
    }
  }

  func testPreviewStateFileStorePersistsOnlyMockMetadata() throws {
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
      detail: "Should never be persisted",
      planName: "ChatGPT Plus",
      symbolName: "person.crop.circle",
      accent: .orange,
      usage: accounts[0].usage,
      source: .codexHome(path: "/private/outside-repository"),
      identityHash: "redacted"
    )
    let unsafeState = PreviewState(
      accounts: [realAccount],
      currentAccountID: realAccount.id
    )

    XCTAssertThrowsError(try persistence.save(unsafeState)) { error in
      XCTAssertEqual(error as? PreviewStatePersistenceError, .unsupportedAccountSource)
    }
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
