import Darwin
import Foundation
import XCTest

@testable import SwitchGPTLifecycleContract

final class UpgradeLifecycleTests: XCTestCase {
  func testStableFingerprintSurvivesAuthRefreshWithoutPersistingSourceFields() throws {
    let first = try StableAccountIdentityFingerprint(
      provider: " ChatGPT ",
      accountID: "account-a",
      subject: "subject-a",
      email: "Person@example.com"
    )
    let refreshed = try StableAccountIdentityFingerprint(
      provider: "chatgpt",
      accountID: "account-a",
      subject: "subject-a",
      email: "person@example.com"
    )
    let changed = try StableAccountIdentityFingerprint(
      provider: "chatgpt",
      accountID: "account-b",
      subject: "subject-b",
      email: "person@example.com"
    )

    XCTAssertEqual(first, refreshed)
    XCTAssertNotEqual(first, changed)
    XCTAssertEqual(first.rawValue.count, 64)

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .upgradeLifecycle
    )
    let store = try StableAccountIdentityFingerprintStore(sessionURL: recorder.sessionURL)
    XCTAssertEqual(try store.record(first), .recorded)
    XCTAssertEqual(try store.record(refreshed), .alreadyRecorded)
    XCTAssertEqual(try store.read(), first)

    let storedData = try Data(
      contentsOf: store.directoryURL.appendingPathComponent("account.fingerprint"))
    XCTAssertFalse(String(decoding: storedData, as: UTF8.self).contains("account-a"))
    XCTAssertFalse(String(decoding: storedData, as: UTF8.self).contains("subject-a"))
    XCTAssertFalse(String(decoding: storedData, as: UTF8.self).contains("person@example.com"))
    XCTAssertThrowsError(try store.record(changed)) {
      XCTAssertEqual(
        $0 as? StableAccountIdentityFingerprintError,
        .identityChanged
      )
    }
  }

  func testUpgradeRunsOldUnregisterThenSeparateInstallThenCandidateRegister() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let report = fixture.controller.run(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )

    XCTAssertEqual(report.outcome, .upgradeCommitted)
    XCTAssertEqual(report.phase, .committed)
    XCTAssertEqual(report.oldBundleRetained, true)
    XCTAssertEqual(fixture.platform.registeredBundle, fixture.candidateBundle)
    XCTAssertTrue(fixture.platform.installedArtifactIDs.contains(fixture.oldBundle.artifactID))
    XCTAssertTrue(
      fixture.platform.installedArtifactIDs.contains(fixture.candidateBundle.artifactID))
    XCTAssertTrue(try fixture.recorder.hasReservation(.registration))
    XCTAssertTrue(try fixture.recorder.hasReservation(.unregistration))
    XCTAssertEqual(try fixture.journal.load()?.phase, .committed)

    let mutationCalls = fixture.platform.calls.filter {
      $0 == "unregister" || $0 == "install" || $0 == "register"
    }
    XCTAssertEqual(mutationCalls, ["unregister", "install", "register"])
    XCTAssertEqual(fixture.platform.overwriteAttempts, 0)
  }

  func testCandidateValidationStopsBeforeAnyLedgerOrServiceMutation() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.platform.validationShouldFail = true

    let report = fixture.controller.run(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )

    XCTAssertEqual(report.outcome, .candidateValidationFailed)
    XCTAssertNil(try fixture.journal.load())
    XCTAssertFalse(try fixture.recorder.hasReservation(.registration))
    XCTAssertFalse(try fixture.recorder.hasReservation(.unregistration))
    XCTAssertEqual(fixture.platform.registeredBundle, fixture.oldBundle)
    XCTAssertEqual(
      fixture.platform.installedArtifactIDs,
      Set([fixture.oldBundle.artifactID])
    )
    XCTAssertFalse(fixture.platform.calls.contains("unregister"))
    XCTAssertFalse(fixture.platform.calls.contains("install"))
    XCTAssertFalse(fixture.platform.calls.contains("register"))
  }

  func testUnregistrationFailureFailsClosedAndRetainsOldExecutable() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.platform.leaveServiceEnabledAfterUnregister = true

    let report = fixture.controller.run(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )

    XCTAssertEqual(report.outcome, .oldServiceUnregistrationUnconfirmed)
    XCTAssertEqual(report.phase, .manualRecoveryRequired)
    XCTAssertEqual(report.oldBundleRetained, true)
    XCTAssertTrue(try fixture.recorder.hasReservation(.unregistration))
    XCTAssertFalse(try fixture.recorder.hasReservation(.registration))
    XCTAssertEqual(fixture.platform.registeredBundle, fixture.oldBundle)
    XCTAssertFalse(fixture.platform.calls.contains("install"))
    XCTAssertFalse(fixture.platform.calls.contains("register"))
    XCTAssertEqual(try fixture.journal.load()?.failure, .oldServiceUnregistrationUnconfirmed)
  }

  func testCandidateInstallFailureLeavesServiceUnregisteredButOldBundleAvailable() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.platform.installShouldFail = true

    let report = fixture.controller.run(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )

    XCTAssertEqual(report.outcome, .candidateInstallationFailed)
    XCTAssertEqual(report.phase, .manualRecoveryRequired)
    XCTAssertEqual(report.oldBundleRetained, true)
    XCTAssertEqual(fixture.platform.registeredBundle, nil)
    XCTAssertTrue(try fixture.recorder.hasReservation(.unregistration))
    XCTAssertFalse(try fixture.recorder.hasReservation(.registration))
    XCTAssertEqual(try fixture.journal.load()?.failure, .candidateInstallationFailed)
  }

  func testApprovalOrRegistrationFailureDoesNotRetryOrDeleteOldBundle() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.platform.candidateRegistrationStatus = .requiresApproval

    let report = fixture.controller.run(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )

    XCTAssertEqual(report.outcome, .candidateRegistrationUnconfirmed)
    XCTAssertEqual(report.phase, .manualRecoveryRequired)
    XCTAssertTrue(try fixture.recorder.hasReservation(.registration))
    XCTAssertTrue(try fixture.recorder.hasReservation(.unregistration))
    XCTAssertTrue(fixture.platform.installedArtifactIDs.contains(fixture.oldBundle.artifactID))
    XCTAssertTrue(
      fixture.platform.installedArtifactIDs.contains(fixture.candidateBundle.artifactID))

    let beforeRetry = fixture.platform.calls.count
    let retryReport = fixture.controller.run(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )
    XCTAssertEqual(retryReport.outcome, .manualRecoveryRequired)
    XCTAssertEqual(fixture.platform.calls.count, beforeRetry)
  }

  func testRecoveryOnlyFinalizesCandidateAlreadyRegisteredBeforeCrash() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    try fixture.journal.prepare(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )
    XCTAssertTrue(try fixture.recorder.reserve(.unregistration))
    try fixture.platform.unregisterCurrentService()
    try fixture.journal.mark(.oldServiceUnregistered)
    try fixture.platform.installCandidate(
      fixture.candidateBundle,
      preserving: fixture.oldBundle
    )
    try fixture.journal.mark(.candidateInstalled)
    XCTAssertTrue(try fixture.recorder.reserve(.registration))
    try fixture.platform.registerCandidate(fixture.candidateBundle)

    let callCountBeforeRecovery = fixture.platform.calls.count
    let report = fixture.controller.recover(
      currentIdentityFingerprint: fixture.identityFingerprint
    )

    XCTAssertEqual(report.outcome, .upgradeCommitted)
    XCTAssertEqual(report.phase, .committed)
    XCTAssertEqual(try fixture.journal.load()?.phase, .committed)
    XCTAssertEqual(fixture.platform.calls.count, callCountBeforeRecovery + 3)
    XCTAssertEqual(
      Array(fixture.platform.calls.suffix(3)),
      [
        "read", "verify:\(fixture.oldBundle.artifactID)",
        "verify:\(fixture.candidateBundle.artifactID)",
      ]
    )
    XCTAssertFalse(Array(fixture.platform.calls.suffix(3)).contains("unregister"))
    XCTAssertFalse(Array(fixture.platform.calls.suffix(3)).contains("register"))
  }

  func testRecoveryIdentityMismatchStopsWithoutDesktopMutation() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.journal.prepare(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )
    let changedIdentity = try StableAccountIdentityFingerprint(
      provider: "chatgpt",
      accountID: "account-b",
      subject: "subject-b"
    )

    let report = fixture.controller.recover(currentIdentityFingerprint: changedIdentity)

    XCTAssertEqual(report.outcome, .manualRecoveryRequired)
    XCTAssertEqual(report.failure, .identityChanged)
    XCTAssertEqual(try fixture.journal.load()?.failure, .identityChanged)
    XCTAssertEqual(fixture.platform.calls, [])
  }

  func testSameArtifactSlotIsRejectedBeforePreparingUpgrade() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let sameSlotCandidate = try LifecycleBundleDescriptor(
      bundleIdentifier: fixture.candidateBundle.bundleIdentifier,
      version: "2.1",
      executableName: fixture.candidateBundle.executableName,
      artifactID: fixture.oldBundle.artifactID
    )

    let report = fixture.controller.run(
      oldBundle: fixture.oldBundle,
      candidateBundle: sameSlotCandidate,
      identityFingerprint: fixture.identityFingerprint
    )

    XCTAssertEqual(report.outcome, .preflightFailed)
    XCTAssertNil(try fixture.journal.load())
    XCTAssertEqual(fixture.platform.calls, [])
  }

  func testCorruptedUpgradeJournalFailsClosed() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.journal.prepare(
      oldBundle: fixture.oldBundle,
      candidateBundle: fixture.candidateBundle,
      identityFingerprint: fixture.identityFingerprint
    )
    let prepared = fixture.journal.directoryURL.appendingPathComponent("prepared.marker")
    try Data("corrupt\n".utf8).write(to: prepared)
    XCTAssertEqual(prepared.path.withCString { chmod($0, 0o600) }, 0)

    XCTAssertThrowsError(try fixture.journal.load()) {
      XCTAssertEqual(
        $0 as? LifecycleUpgradeJournalError,
        .inconsistentState
      )
    }
    let report = fixture.controller.recover(
      currentIdentityFingerprint: fixture.identityFingerprint
    )
    XCTAssertEqual(report.outcome, .ledgerUnavailable)
    XCTAssertEqual(fixture.platform.calls, [])
  }

  private func makeFixture() throws -> Fixture {
    let root = try makeRoot()
    let recorder = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .upgradeLifecycle
    )
    let journal = try LifecycleUpgradeJournal(sessionURL: recorder.sessionURL)
    let oldBundle = try LifecycleBundleDescriptor(
      bundleIdentifier: "com.switchgpt.lifecycle-validation",
      version: "1.0",
      executableName: "SwitchGPTBootRecovery",
      artifactID: "old-bundle"
    )
    let candidateBundle = try LifecycleBundleDescriptor(
      bundleIdentifier: "com.switchgpt.lifecycle-validation",
      version: "2.0",
      executableName: "SwitchGPTBootRecovery",
      artifactID: "candidate-bundle"
    )
    let platform = FixtureUpgradePlatform(
      oldBundle: oldBundle,
      candidateBundle: candidateBundle
    )
    return Fixture(
      root: root,
      recorder: recorder,
      journal: journal,
      oldBundle: oldBundle,
      candidateBundle: candidateBundle,
      identityFingerprint: try StableAccountIdentityFingerprint(
        provider: "chatgpt",
        accountID: "account-a",
        subject: "subject-a",
        email: "person@example.com"
      ),
      platform: platform,
      controller: LifecycleUpgradeController(
        platform: platform,
        attemptRecorder: recorder,
        journal: journal
      )
    )
  }

  private func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "switchgpt-safety-upgrade-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    XCTAssertEqual(root.path.withCString { chmod($0, 0o700) }, 0)
    return root
  }
}

private struct Fixture {
  let root: URL
  let recorder: PersistentActivationAttemptRecorder
  let journal: LifecycleUpgradeJournal
  let oldBundle: LifecycleBundleDescriptor
  let candidateBundle: LifecycleBundleDescriptor
  let identityFingerprint: StableAccountIdentityFingerprint
  let platform: FixtureUpgradePlatform
  let controller: LifecycleUpgradeController
}

private final class FixtureUpgradePlatform: LifecycleUpgradePlatform {
  private let oldBundle: LifecycleBundleDescriptor
  private let candidateBundle: LifecycleBundleDescriptor

  var installedArtifactIDs: Set<String>
  var registeredBundle: LifecycleBundleDescriptor?
  var calls: [String] = []
  var validationShouldFail = false
  var leaveServiceEnabledAfterUnregister = false
  var installShouldFail = false
  var candidateRegistrationStatus: RecoveryServiceStatus = .enabled
  var overwriteAttempts = 0

  init(oldBundle: LifecycleBundleDescriptor, candidateBundle: LifecycleBundleDescriptor) {
    self.oldBundle = oldBundle
    self.candidateBundle = candidateBundle
    installedArtifactIDs = [oldBundle.artifactID]
    registeredBundle = oldBundle
  }

  func readSnapshot() throws -> LifecycleUpgradeServiceSnapshot {
    calls.append("read")
    return LifecycleUpgradeServiceSnapshot(
      status: registeredBundle == nil ? .notRegistered : registrationStatus,
      registeredBundle: registeredBundle
    )
  }

  func validateCandidate(
    _ candidateBundle: LifecycleBundleDescriptor,
    preserving oldBundle: LifecycleBundleDescriptor
  ) throws {
    calls.append("validate")
    if validationShouldFail || candidateBundle.artifactID == oldBundle.artifactID {
      throw FixtureError.operationFailed
    }
  }

  func unregisterCurrentService() throws {
    calls.append("unregister")
    if !leaveServiceEnabledAfterUnregister {
      registeredBundle = nil
    }
  }

  func installCandidate(
    _ candidateBundle: LifecycleBundleDescriptor,
    preserving oldBundle: LifecycleBundleDescriptor
  ) throws {
    calls.append("install")
    guard candidateBundle.artifactID != oldBundle.artifactID else {
      overwriteAttempts += 1
      throw FixtureError.operationFailed
    }
    if installShouldFail {
      throw FixtureError.operationFailed
    }
    installedArtifactIDs.insert(candidateBundle.artifactID)
  }

  func verifyExecutable(_ bundle: LifecycleBundleDescriptor) throws -> Bool {
    calls.append("verify:\(bundle.artifactID)")
    return installedArtifactIDs.contains(bundle.artifactID)
  }

  func registerCandidate(_ candidateBundle: LifecycleBundleDescriptor) throws {
    calls.append("register")
    registeredBundle = candidateBundle
    registrationStatus = candidateRegistrationStatus
  }

  private var registrationStatus: RecoveryServiceStatus = .enabled
}

private enum FixtureError: Error {
  case operationFailed
}
