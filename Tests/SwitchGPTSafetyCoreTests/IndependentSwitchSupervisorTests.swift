import Foundation
import XCTest

@testable import SwitchGPTSafetyCore

final class IndependentSwitchSupervisorTests: XCTestCase {
  private let accountA = IdentityID(rawValue: "account-a")!
  private let accountB = IdentityID(rawValue: "account-b")!
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for directory in temporaryDirectories {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
  }

  func testIndependentApplicationArmsRecoveryBeforeFirstDesktopSideEffect() throws {
    let harness = try makeHarness()
    var desktopStateWhenArmed: FixtureDesktop.State?
    harness.recovery.onArm = {
      desktopStateWhenArmed = try harness.desktop.snapshot()
    }

    let result = try harness.supervisor.beginSwitch(from: accountA, to: accountB)

    XCTAssertEqual(result.phase, .committed)
    XCTAssertEqual(harness.recovery.armCount, 1)
    XCTAssertEqual(desktopStateWhenArmed?.installedIdentity, accountA)
    XCTAssertEqual(desktopStateWhenArmed?.isRunning, true)
    XCTAssertEqual(desktopStateWhenArmed?.stopCount, 0)
    XCTAssertEqual(desktopStateWhenArmed?.startsByIdentity, [:])
  }

  func testRecoveryArmFailureLeavesDesktopUntouched() throws {
    let harness = try makeHarness()
    harness.recovery.error = TestError.armFailed

    XCTAssertThrowsError(try harness.supervisor.beginSwitch(from: accountA, to: accountB))

    let state = try harness.desktop.snapshot()
    XCTAssertEqual(state.installedIdentity, accountA)
    XCTAssertTrue(state.isRunning)
    XCTAssertEqual(state.stopCount, 0)
    XCTAssertTrue(state.startsByIdentity.isEmpty)
    XCTAssertEqual(try harness.store.load()?.phase, .prepared)
  }

  func testSubmittedJobIsRejectedBeforePersistentOrDesktopSideEffects() throws {
    let harness = try makeHarness(launchMechanism: .submittedJob)

    XCTAssertThrowsError(
      try harness.supervisor.beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .prohibitedLaunchMechanism)
    }
    try assertNoSideEffects(harness)
  }

  func testEmbeddedDevelopmentHostIsRejected() throws {
    let harness = try makeHarness(launchMechanism: .embeddedDevelopmentHost)

    XCTAssertThrowsError(
      try harness.supervisor.beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .prohibitedLaunchMechanism)
    }
    try assertNoSideEffects(harness)
  }

  func testTargetApplicationAsHostIsRejected() throws {
    let harness = try makeHarness(
      hostBundleIdentifier: "com.openai.codex",
      expectedHostBundleIdentifier: "com.switchgpt.app"
    )

    XCTAssertThrowsError(
      try harness.supervisor.beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .unexpectedHostIdentity)
    }
    try assertNoSideEffects(harness)
  }

  func testExecutableOutsideExpectedHostBundleIsRejected() throws {
    let harness = try makeHarness(executableInsideHostBundle: false)

    XCTAssertThrowsError(
      try harness.supervisor.beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .executableOutsideExpectedHost)
    }
    try assertNoSideEffects(harness)
  }

  func testHostNestedInsideTargetApplicationIsRejected() throws {
    let harness = try makeHarness(hostNestedInsideTarget: true)

    XCTAssertThrowsError(
      try harness.supervisor.beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .hostNestedInsideTarget)
    }
    try assertNoSideEffects(harness)
  }

  func testTargetHostedAncestorIsRejected() throws {
    let harness = try makeHarness(targetHostedAncestor: true)

    XCTAssertThrowsError(
      try harness.supervisor.beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .targetHostedAncestor)
    }
    try assertNoSideEffects(harness)
  }

  func testInvalidSignatureIsRejectedBeforeSideEffects() throws {
    let harness = try makeHarness(signatureEvidence: .invalid)

    XCTAssertThrowsError(
      try harness.supervisor.beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .invalidHostSignature)
    }
    try assertNoSideEffects(harness)
  }

  func testWrongSigningTeamIsRejectedBeforeSideEffects() throws {
    let harness = try makeHarness(
      signatureEvidence: .verified(
        teamIdentifier: "OTHERTEAM",
        signingIdentifier: "com.switchgpt.app"
      ))

    XCTAssertThrowsError(
      try harness.supervisor.beginSwitch(from: accountA, to: accountB)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .invalidHostSignature)
    }
    try assertNoSideEffects(harness)
  }

  private func makeHarness(
    launchMechanism: SupervisorLaunchMechanism = .application,
    hostBundleIdentifier: String = "com.switchgpt.app",
    expectedHostBundleIdentifier: String = "com.switchgpt.app",
    executableInsideHostBundle: Bool = true,
    hostNestedInsideTarget: Bool = false,
    targetHostedAncestor: Bool = false,
    signatureEvidence: SupervisorSignatureEvidence = .verified(
      teamIdentifier: "SWITCHGPT-SAFETY-FIXTURE",
      signingIdentifier: "com.switchgpt.app"
    )
  ) throws -> SupervisorHarness {
    let root = try makeTemporaryDirectory()
    let targetBundle = root.appendingPathComponent("Applications/ChatGPT.app", isDirectory: true)
    let hostBundle =
      hostNestedInsideTarget
      ? targetBundle.appendingPathComponent("Contents/Helpers/SwitchGPT.app", isDirectory: true)
      : root.appendingPathComponent("Applications/SwitchGPT.app", isDirectory: true)
    let executable =
      executableInsideHostBundle
      ? hostBundle.appendingPathComponent("Contents/MacOS/SwitchGPT")
      : root.appendingPathComponent("tmp/SwitchGPT")
    let targetExecutable = targetBundle.appendingPathComponent("Contents/MacOS/ChatGPT")

    let store = try TransactionStore(directoryURL: root.appendingPathComponent("transaction"))
    let desktop = try FixtureDesktop(
      directoryURL: root.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let recovery = RecordingRecoverySupervisor()
    let evidence = SupervisorHostEvidence(
      hostBundleIdentifier: hostBundleIdentifier,
      expectedHostBundleIdentifier: expectedHostBundleIdentifier,
      targetBundleIdentifier: "com.openai.codex",
      expectedHostTeamIdentifier: "SWITCHGPT-SAFETY-FIXTURE",
      signatureEvidence: signatureEvidence,
      executableURL: executable,
      expectedHostBundleURL: hostBundle,
      targetBundleURL: targetBundle,
      ancestorExecutableURLs: targetHostedAncestor ? [targetExecutable] : [],
      launchMechanism: launchMechanism
    )
    let supervisor = IndependentSwitchSupervisor(
      store: store,
      desktop: desktop,
      hostEvidence: evidence,
      recoverySupervisor: recovery
    )
    return SupervisorHarness(
      store: store,
      desktop: desktop,
      recovery: recovery,
      supervisor: supervisor
    )
  }

  private func assertNoSideEffects(_ harness: SupervisorHarness) throws {
    XCTAssertNil(try harness.store.load())
    XCTAssertEqual(harness.recovery.armCount, 0)
    let state = try harness.desktop.snapshot()
    XCTAssertEqual(state.installedIdentity, accountA)
    XCTAssertTrue(state.isRunning)
    XCTAssertEqual(state.stopCount, 0)
    XCTAssertTrue(state.startsByIdentity.isEmpty)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-supervisor-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }
}

private enum TestError: Error {
  case armFailed
}

private final class RecordingRecoverySupervisor: OneShotRecoverySupervisor {
  var armCount = 0
  var error: Error?
  var onArm: (() throws -> Void)?

  func armAndWaitUntilReady() throws {
    armCount += 1
    if let error { throw error }
    try onArm?()
  }
}

private struct SupervisorHarness {
  let store: TransactionStore
  let desktop: FixtureDesktop
  let recovery: RecordingRecoverySupervisor
  let supervisor: IndependentSwitchSupervisor
}
