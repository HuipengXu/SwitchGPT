import Foundation
import SwitchGPTLifecycleContract
import XCTest

@testable import SwitchGPTSafetyCore

final class BootRecoveryEntryTests: XCTestCase {
  private let accountA = IdentityID(rawValue: "account-a")!
  private let accountB = IdentityID(rawValue: "account-b")!
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for directory in temporaryDirectories {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
  }

  func testInvalidInvocationDoesNotReadOrMutateState() throws {
    let harness = try makeHarness()

    XCTAssertEqual(run(arguments: ["begin-switch"], harness: harness), .invalidInvocation)
    try assertDesktopUnchanged(harness.desktop)
    XCTAssertNil(try harness.store.load())
  }

  func testMissingTransactionReturnsInactiveWithoutDesktopSideEffects() throws {
    let harness = try makeHarness()

    XCTAssertEqual(run(harness: harness), .inactive)
    try assertDesktopUnchanged(harness.desktop)
  }

  func testCommittedTransactionReturnsTerminalWithoutRollback() throws {
    let harness = try makeHarness()
    _ = try SwitchTransactionEngine(store: harness.store, desktop: harness.desktop)
      .beginSwitch(from: accountA, to: accountB)

    XCTAssertEqual(run(harness: harness), .terminal)
    let state = try harness.desktop.snapshot()
    XCTAssertEqual(state.installedIdentity, accountB)
    XCTAssertEqual(state.startsByIdentity[accountB.rawValue], 1)
    XCTAssertNil(state.startsByIdentity[accountA.rawValue])
  }

  func testInterruptedTransactionRecoversOnceAcrossRepeatedEntry() throws {
    let harness = try makeHarness(crashAt: .afterTargetStarted)
    XCTAssertThrowsError(
      try harness.engine.beginSwitch(from: accountA, to: accountB)
    )

    XCTAssertEqual(run(harness: harness), .recovered)
    XCTAssertEqual(run(harness: harness), .terminal)
    let state = try harness.desktop.snapshot()
    XCTAssertEqual(state.installedIdentity, accountA)
    XCTAssertEqual(state.startsByIdentity[accountB.rawValue], 1)
    XCTAssertEqual(state.startsByIdentity[accountA.rawValue], 1)
  }

  func testCorruptedStateReturnsUnsafeWithoutDesktopSideEffects() throws {
    let harness = try makeHarness()
    try harness.store.save(TransactionRecord(sourceIdentity: accountA, targetIdentity: accountB))
    try Data("{".utf8).write(to: harness.store.stateURL, options: .atomic)
    _ = harness.store.stateURL.path.withCString { chmod($0, 0o600) }

    XCTAssertEqual(run(harness: harness), .unsafeState)
    try assertDesktopUnchanged(harness.desktop)
  }

  private func run(
    arguments: [String] = [BootRecoveryEntry.command],
    harness: BootEntryHarness
  ) -> BootRecoveryOutcome {
    BootRecoveryEntry.run(
      arguments: arguments,
      store: harness.store,
      desktop: harness.desktop
    )
  }

  private func makeHarness(crashAt checkpoint: SafetyCheckpoint? = nil) throws
    -> BootEntryHarness
  {
    let root = try makeTemporaryDirectory()
    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let engine = SwitchTransactionEngine(store: store, desktop: desktop) { point in
      if point == checkpoint { throw SimulatedProcessExit(at: point) }
    }
    return BootEntryHarness(store: store, desktop: desktop, engine: engine)
  }

  private func assertDesktopUnchanged(_ desktop: FixtureDesktop) throws {
    let state = try desktop.snapshot()
    XCTAssertEqual(state.installedIdentity, accountA)
    XCTAssertTrue(state.isRunning)
    XCTAssertEqual(state.stopCount, 0)
    XCTAssertTrue(state.startsByIdentity.isEmpty)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }
}

private struct BootEntryHarness {
  let store: TransactionStore
  let desktop: FixtureDesktop
  let engine: SwitchTransactionEngine
}
