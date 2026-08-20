import Darwin
import Foundation
@_spi(SafetyTesting) @testable import SwitchGPTSafetyCore
import XCTest

final class TransactionStoreDurabilityTests: XCTestCase {
  private enum TestFailure: Error {
    case injectedWriteFailure
  }

  private let accountA = IdentityID(rawValue: "account-a")!
  private let accountB = IdentityID(rawValue: "account-b")!
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for directory in temporaryDirectories {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
  }

  func testTruncatedStateStopsRecoveryBeforeDesktopSideEffects() throws {
    let harness = try makePersistedHarness()
    try overwritePrivate(Data("{".utf8), at: harness.store.stateURL)

    try assertRecoveryRejected(
      harness,
      expectedError: .corruptedPersistedState
    )
  }

  func testChecksumMismatchStopsRecoveryBeforeDesktopSideEffects() throws {
    let harness = try makePersistedHarness()
    let data = try Data(contentsOf: harness.store.stateURL)
    var envelope = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var record = try XCTUnwrap(envelope["record"] as? [String: Any])
    record["phase"] = TransactionPhase.startingTarget.rawValue
    envelope["record"] = record
    try overwritePrivate(
      JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]),
      at: harness.store.stateURL
    )

    try assertRecoveryRejected(
      harness,
      expectedError: .corruptedPersistedState
    )
  }

  func testOversizedStateStopsRecoveryBeforeDesktopSideEffects() throws {
    let harness = try makePersistedHarness()
    try overwritePrivate(
      Data(repeating: 0x41, count: TransactionStore.maximumStateBytes + 1),
      at: harness.store.stateURL
    )

    try assertRecoveryRejected(
      harness,
      expectedError: .corruptedPersistedState
    )
  }

  func testStateSymbolicLinkStopsRecoveryBeforeDesktopSideEffects() throws {
    let harness = try makePersistedHarness()
    let linkedStateURL = harness.root.appendingPathComponent("linked-state.json")
    try FileManager.default.copyItem(at: harness.store.stateURL, to: linkedStateURL)
    try FileManager.default.removeItem(at: harness.store.stateURL)
    try FileManager.default.createSymbolicLink(
      at: harness.store.stateURL,
      withDestinationURL: linkedStateURL
    )

    try assertRecoveryRejected(harness, expectedError: .unsafeStorage)
  }

  func testStateHardLinkStopsRecoveryBeforeDesktopSideEffects() throws {
    let harness = try makePersistedHarness()
    try FileManager.default.linkItem(
      at: harness.store.stateURL,
      to: harness.root.appendingPathComponent("second-state-link.json")
    )

    try assertRecoveryRejected(harness, expectedError: .unsafeStorage)
  }

  func testStateWithBroadPermissionsStopsRecoveryBeforeDesktopSideEffects() throws {
    let harness = try makePersistedHarness()
    try changeMode(0o644, at: harness.store.stateURL)

    try assertRecoveryRejected(harness, expectedError: .unsafeStorage)
  }

  func testLockSymbolicLinkStopsSwitchBeforeDesktopSideEffects() throws {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let linkedLockURL = root.appendingPathComponent("linked-lock")
    try Data().write(to: linkedLockURL)
    try changeMode(0o600, at: linkedLockURL)
    try FileManager.default.createSymbolicLink(
      at: store.lockURL,
      withDestinationURL: linkedLockURL
    )

    XCTAssertThrowsError(
      try SwitchTransactionEngine(store: store, desktop: desktop)
        .beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SafetyError, .unsafeStorage)
    }
    try assertDesktopUnchanged(desktop)
  }

  func testLockWithBroadPermissionsStopsSwitchBeforeDesktopSideEffects() throws {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    try Data().write(to: store.lockURL)
    try changeMode(0o644, at: store.lockURL)

    XCTAssertThrowsError(
      try SwitchTransactionEngine(store: store, desktop: desktop)
        .beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SafetyError, .unsafeStorage)
    }
    try assertDesktopUnchanged(desktop)
  }

  func testDirectoryReplacedBySymbolicLinkStopsSwitchBeforeCreatingLock() throws {
    let root = try makeTemporaryDirectory()
    let transactionURL = root.appendingPathComponent("transaction")
    let store = try TransactionStore(directoryURL: transactionURL)
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let replacementURL = root.appendingPathComponent("replacement")
    try FileManager.default.createDirectory(at: replacementURL, withIntermediateDirectories: true)
    try changeMode(0o700, at: replacementURL)
    try FileManager.default.removeItem(at: transactionURL)
    try FileManager.default.createSymbolicLink(
      at: transactionURL,
      withDestinationURL: replacementURL
    )

    XCTAssertThrowsError(
      try SwitchTransactionEngine(store: store, desktop: desktop)
        .beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SafetyError, .unsafeStorage)
    }
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: replacementURL.appendingPathComponent("transaction.lock").path
      )
    )
    try assertDesktopUnchanged(desktop)
  }

  func testPreexistingBroadDirectoryPermissionsAreRejected() throws {
    let root = try makeTemporaryDirectory()
    let transactionURL = root.appendingPathComponent("transaction")
    try FileManager.default.createDirectory(at: transactionURL, withIntermediateDirectories: true)
    try changeMode(0o755, at: transactionURL)

    XCTAssertThrowsError(try TransactionStore(directoryURL: transactionURL)) { error in
      XCTAssertEqual(error as? SafetyError, .unsafeStorage)
    }
    XCTAssertEqual(try mode(of: transactionURL), 0o755)
  }

  func testFailureBeforeRenameLeavesNoStateAndNoDesktopSideEffects() throws {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(
      directoryURL: root.appendingPathComponent("transaction")
    ) { checkpoint in
      if case .afterTemporaryFileSynchronized = checkpoint {
        throw TestFailure.injectedWriteFailure
      }
    }
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )

    XCTAssertThrowsError(
      try SwitchTransactionEngine(store: store, desktop: desktop)
        .beginSwitch(from: accountA, to: accountB)
    )
    XCTAssertNil(try TransactionStore(directoryURL: store.directoryURL).load())
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.directoryURL.path)
      .filter { $0.hasSuffix(".tmp") }
    XCTAssertTrue(leftovers.isEmpty)
    try assertDesktopUnchanged(desktop)
  }

  func testFailureAfterDirectorySyncLeavesRecoverableDurableState() throws {
    let root = try makeTemporaryDirectory()
    let transactionURL = root.appendingPathComponent("transaction")
    let store = try TransactionStore(directoryURL: transactionURL) { checkpoint in
      if case .afterDirectorySynchronized = checkpoint {
        throw TestFailure.injectedWriteFailure
      }
    }
    let record = TransactionRecord(sourceIdentity: accountA, targetIdentity: accountB)

    XCTAssertThrowsError(try store.save(record))
    let recoveredStore = try TransactionStore(directoryURL: transactionURL)
    let durableRecord = try XCTUnwrap(recoveredStore.load())
    XCTAssertEqual(durableRecord.id, record.id)
    XCTAssertEqual(durableRecord.sourceIdentity, record.sourceIdentity)
    XCTAssertEqual(durableRecord.targetIdentity, record.targetIdentity)
    XCTAssertEqual(durableRecord.recoveryIdentity, record.recoveryIdentity)
    XCTAssertEqual(durableRecord.mode, record.mode)
    XCTAssertEqual(durableRecord.phase, record.phase)
    XCTAssertEqual(durableRecord.targetLaunchAttempts, record.targetLaunchAttempts)
    XCTAssertEqual(durableRecord.rollbackLaunchAttempts, record.rollbackLaunchAttempts)
    XCTAssertEqual(durableRecord.targetWasInstalled, record.targetWasInstalled)
    XCTAssertEqual(durableRecord.failureReason, record.failureReason)

    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let result = try SwitchTransactionEngine(store: recoveredStore, desktop: desktop).recover()
    let state = try desktop.snapshot()
    XCTAssertEqual(result.phase, .rolledBack)
    XCTAssertEqual(result.mode, .recoveryOnly)
    XCTAssertEqual(state.installedIdentity, accountA)
    XCTAssertEqual(state.startsByIdentity[accountA.rawValue], 1)
    XCTAssertNil(state.startsByIdentity[accountB.rawValue])
  }

  private func makePersistedHarness() throws -> DurabilityHarness {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    try store.save(TransactionRecord(sourceIdentity: accountA, targetIdentity: accountB))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    return DurabilityHarness(root: root, store: store, desktop: desktop)
  }

  private func assertRecoveryRejected(
    _ harness: DurabilityHarness,
    expectedError: SafetyError
  ) throws {
    XCTAssertThrowsError(
      try SwitchTransactionEngine(store: harness.store, desktop: harness.desktop).recover()
    ) { error in
      XCTAssertEqual(error as? SafetyError, expectedError)
    }
    try assertDesktopUnchanged(harness.desktop)
  }

  private func assertDesktopUnchanged(_ desktop: FixtureDesktop) throws {
    let state = try desktop.snapshot()
    XCTAssertEqual(state.installedIdentity, accountA)
    XCTAssertTrue(state.isRunning)
    XCTAssertEqual(state.stopCount, 0)
    XCTAssertTrue(state.startsByIdentity.isEmpty)
  }

  private func overwritePrivate(_ data: Data, at url: URL) throws {
    try data.write(to: url, options: .atomic)
    try changeMode(0o600, at: url)
  }

  private func changeMode(_ mode: mode_t, at url: URL) throws {
    guard url.path.withCString({ chmod($0, mode) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private func mode(of url: URL) throws -> mode_t {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return mode_t((attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }
}

private struct DurabilityHarness {
  let root: URL
  let store: TransactionStore
  let desktop: FixtureDesktop
}
