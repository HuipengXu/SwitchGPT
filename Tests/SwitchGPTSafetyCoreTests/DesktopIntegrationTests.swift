import CryptoKit
import Darwin
import Foundation
import SwitchGPTSafetyCore
import XCTest

@testable import SwitchGPTDesktopIntegration

final class DesktopIntegrationTests: XCTestCase {
  func testChatGPTCompatibilityClassifiesValidatedAndUnvalidatedVersions() {
    XCTAssertTrue(
      ChatGPTDesktopCompatibility.supports(version: "26.810.52044", build: "6662")
    )
    XCTAssertEqual(
      ChatGPTDesktopCompatibility.assessment(version: "26.810.52044", build: "6662"),
      .validated(ChatGPTDesktopVersion(version: "26.810.52044", build: "6662"))
    )
    XCTAssertFalse(
      ChatGPTDesktopCompatibility.supports(version: "26.810.52044", build: "6663")
    )
    XCTAssertEqual(
      ChatGPTDesktopCompatibility.assessment(version: "26.810.52044", build: "6663"),
      .unvalidated(version: "26.810.52044", build: "6663")
    )
    XCTAssertFalse(
      ChatGPTDesktopCompatibility.supports(version: "26.811.00000", build: "6662")
    )
    XCTAssertEqual(
      ChatGPTDesktopCompatibility.assessment(version: "26.811.00000", build: "6662"),
      .unvalidated(version: "26.811.00000", build: "6662")
    )
    XCTAssertFalse(ChatGPTDesktopCompatibility.supports(version: nil, build: "6662"))
    XCTAssertFalse(ChatGPTDesktopCompatibility.supports(version: "26.810.52044", build: nil))
    XCTAssertEqual(
      ChatGPTDesktopCompatibility.assessment(version: nil, build: "6662"),
      .unvalidated(version: nil, build: "6662")
    )
  }

  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for directory in temporaryDirectories {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
  }

  func testTargetInstallSnapshotsOriginalAndRollbackRestoresIt() throws {
    let fixture = try makeFixture()
    let process = FixtureProcessController()
    let adapter = try RealChatGPTDesktopAdapter(
      sourceIdentity: fixture.identityA,
      profiles: fixture.profiles,
      processController: process,
      identityReader: PinnedAuthenticationIdentityReader(
        authenticationFileURL: fixture.activeAuthenticationURL
      ),
      authenticationInstaller: fixture.installer
    )

    try adapter.stop()
    try adapter.install(identity: fixture.identityB)
    XCTAssertEqual(try adapter.currentIdentity(), fixture.identityB)
    XCTAssertTrue(try fixture.installer.hasRecoverySnapshot())
    try adapter.start()

    try adapter.stop()
    try adapter.install(identity: fixture.identityA)
    XCTAssertEqual(try adapter.currentIdentity(), fixture.identityA)
    try adapter.start()

    XCTAssertEqual(process.stopCount, 2)
    XCTAssertEqual(process.startCount, 2)
  }

  func testRecoveryBeforeTargetInstallIsNoOpForVerifiedSource() throws {
    let fixture = try makeFixture()
    let process = FixtureProcessController()
    let adapter = try RealChatGPTDesktopAdapter(
      sourceIdentity: fixture.identityA,
      profiles: fixture.profiles,
      processController: process,
      identityReader: PinnedAuthenticationIdentityReader(
        authenticationFileURL: fixture.activeAuthenticationURL
      ),
      authenticationInstaller: fixture.installer
    )

    try adapter.install(identity: fixture.identityA)

    XCTAssertFalse(try fixture.installer.hasRecoverySnapshot())
    XCTAssertEqual(try adapter.currentIdentity(), fixture.identityA)
  }

  func testMissingSnapshotFailsClosedWhenActiveIdentityIsNotSource() throws {
    let fixture = try makeFixture(activeIdentity: .b)
    let adapter = try RealChatGPTDesktopAdapter(
      sourceIdentity: fixture.identityA,
      profiles: fixture.profiles,
      processController: FixtureProcessController(),
      identityReader: PinnedAuthenticationIdentityReader(
        authenticationFileURL: fixture.activeAuthenticationURL
      ),
      authenticationInstaller: fixture.installer
    )

    XCTAssertThrowsError(try adapter.install(identity: fixture.identityA)) { error in
      XCTAssertEqual(error as? DesktopIntegrationError, .missingRecoverySnapshot)
    }
    XCTAssertEqual(try adapter.currentIdentity(), fixture.identityB)
  }

  func testInstallerRejectsBroadPermissionsBeforeCreatingSnapshot() throws {
    let fixture = try makeFixture()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: fixture.activeAuthenticationURL.path
    )

    XCTAssertThrowsError(try fixture.installer.snapshotActiveStateIfNeeded()) { error in
      XCTAssertEqual(error as? DesktopIntegrationError, .insecureAuthenticationFile)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoverySnapshotURL.path))
  }

  func testInstallerRejectsSymlinkSourceWithoutChangingActiveState() throws {
    let fixture = try makeFixture()
    let symlink = fixture.root.appendingPathComponent("linked-auth.json")
    try FileManager.default.createSymbolicLink(
      at: symlink,
      withDestinationURL: fixture.profileBURL
    )
    let before = try Data(contentsOf: fixture.activeAuthenticationURL)

    XCTAssertThrowsError(try fixture.installer.installAuthenticationFile(from: symlink))
    XCTAssertEqual(try Data(contentsOf: fixture.activeAuthenticationURL), before)
  }

  func testIdentityReaderRejectsSymlinkBeforeTransactionCanStart() throws {
    let fixture = try makeFixture()
    let link = fixture.root.appendingPathComponent("active-link.json")
    try FileManager.default.createSymbolicLink(
      at: link,
      withDestinationURL: fixture.activeAuthenticationURL
    )
    let reader = PinnedAuthenticationIdentityReader(authenticationFileURL: link)

    XCTAssertThrowsError(try reader.currentIdentity()) { error in
      XCTAssertEqual(error as? DesktopIntegrationError, .invalidAuthenticationFile)
    }
  }

  func testPrivateProfileArchiveAndSynchronizationRemainPrivateAndAtomic() throws {
    let fixture = try makeFixture()
    let profileDirectory = fixture.root.appendingPathComponent("managed-profile", isDirectory: true)
    try FileManager.default.createDirectory(
      at: profileDirectory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let archivedURL = profileDirectory.appendingPathComponent("auth.json")

    try SecureAuthenticationFileInstaller.archivePrivateAuthenticationFile(
      from: fixture.activeAuthenticationURL,
      to: archivedURL
    )

    XCTAssertEqual(
      try PinnedAuthenticationIdentityReader(authenticationFileURL: archivedURL)
        .currentIdentity(),
      fixture.identityA
    )
    let attributes = try FileManager.default.attributesOfItem(atPath: archivedURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

    try SecureAuthenticationFileInstaller.synchronizePrivateAuthenticationFile(
      from: fixture.profileBURL,
      to: archivedURL
    )
    XCTAssertEqual(
      try PinnedAuthenticationIdentityReader(authenticationFileURL: archivedURL)
        .currentIdentity(),
      fixture.identityB
    )
  }

  func testTerminationFallbackTargetsOnlyOriginalProcessesStillRunning() {
    XCTAssertEqual(
      MacOSChatGPTProcessController.originalProcessesStillRunning(
        original: [101, 102],
        current: [102, 999]
      ),
      [102]
    )
  }

  func testFreshRecoveryProcessRestoresSnapshotAfterTargetInstallCrash() throws {
    let fixture = try makeFixture()
    let transactionStore = try TransactionStore(
      directoryURL: fixture.root.appendingPathComponent("switch-transaction")
    )
    let firstAdapter = try RealChatGPTDesktopAdapter(
      sourceIdentity: fixture.identityA,
      profiles: fixture.profiles,
      processController: FixtureProcessController(),
      identityReader: PinnedAuthenticationIdentityReader(
        authenticationFileURL: fixture.activeAuthenticationURL
      ),
      authenticationInstaller: fixture.installer
    )
    let engine = SwitchTransactionEngine(
      store: transactionStore,
      desktop: firstAdapter
    ) { point in
      if point == .afterTargetInstalled {
        throw SimulatedProcessExit(at: point)
      }
    }

    XCTAssertThrowsError(
      try engine.beginSwitch(from: fixture.identityA, to: fixture.identityB)
    )
    XCTAssertEqual(
      try PinnedAuthenticationIdentityReader(
        authenticationFileURL: fixture.activeAuthenticationURL
      ).currentIdentity(),
      fixture.identityB
    )

    let recoveryProcess = FixtureProcessController(running: false)
    let recoveryAdapter = try RealChatGPTDesktopAdapter(
      sourceIdentity: fixture.identityA,
      profiles: fixture.profiles,
      processController: recoveryProcess,
      identityReader: PinnedAuthenticationIdentityReader(
        authenticationFileURL: fixture.activeAuthenticationURL
      ),
      authenticationInstaller: try SecureAuthenticationFileInstaller(
        activeAuthenticationURL: fixture.activeAuthenticationURL,
        recoverySnapshotURL: fixture.recoverySnapshotURL
      )
    )

    let recovered = try SwitchTransactionEngine(
      store: transactionStore,
      desktop: recoveryAdapter
    ).recover()

    XCTAssertEqual(recovered.phase, .rolledBack)
    XCTAssertEqual(try recoveryAdapter.currentIdentity(), fixture.identityA)
    XCTAssertEqual(recoveryProcess.startCount, 1)
  }

  private func makeFixture(activeIdentity: FixtureIdentity = .a) throws -> IntegrationFixture {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-integration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    temporaryDirectories.append(root)

    let activeURL = root.appendingPathComponent("active-auth.json")
    let profileAURL = root.appendingPathComponent("account-a-auth.json")
    let profileBURL = root.appendingPathComponent("account-b-auth.json")
    try writeAuthentication(email: "a@example.test", to: profileAURL)
    try writeAuthentication(email: "b@example.test", to: profileBURL)
    try FileManager.default.copyItem(
      at: activeIdentity == .a ? profileAURL : profileBURL,
      to: activeURL
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activeURL.path)

    let identityA = identity(for: "a@example.test")
    let identityB = identity(for: "b@example.test")
    let recoveryURL = root.appendingPathComponent("transaction/recovery-auth.json")
    return IntegrationFixture(
      root: root,
      identityA: identityA,
      identityB: identityB,
      activeAuthenticationURL: activeURL,
      profileBURL: profileBURL,
      recoverySnapshotURL: recoveryURL,
      profiles: [
        DesktopCredentialProfile(identity: identityA, authenticationFileURL: profileAURL),
        DesktopCredentialProfile(identity: identityB, authenticationFileURL: profileBURL),
      ],
      installer: try SecureAuthenticationFileInstaller(
        activeAuthenticationURL: activeURL,
        recoverySnapshotURL: recoveryURL
      )
    )
  }

  private func writeAuthentication(email: String, to url: URL) throws {
    let header = Data("{\"alg\":\"none\"}".utf8).base64URLEncodedString()
    let payload = try JSONSerialization.data(withJSONObject: ["email": email])
      .base64URLEncodedString()
    let object: [String: Any] = [
      "auth_mode": "chatgpt",
      "tokens": ["id_token": header + "." + payload + ".fixture"],
    ]
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func identity(for email: String) -> IdentityID {
    let digest = SHA256.hash(data: Data(email.utf8))
    return IdentityID(
      rawValue: digest.map { String(format: "%02x", $0) }.joined().prefix(12).description)!
  }
}

private enum FixtureIdentity { case a, b }

private final class FixtureProcessController: DesktopProcessControlling {
  var running: Bool
  var stopCount = 0
  var startCount = 0

  init(running: Bool = true) {
    self.running = running
  }

  func isRunning() throws -> Bool { running }
  func terminateAndWait() throws {
    running = false
    stopCount += 1
  }
  func launchAndWait() throws {
    running = true
    startCount += 1
  }
}

private struct IntegrationFixture {
  let root: URL
  let identityA: IdentityID
  let identityB: IdentityID
  let activeAuthenticationURL: URL
  let profileBURL: URL
  let recoverySnapshotURL: URL
  let profiles: [DesktopCredentialProfile]
  let installer: SecureAuthenticationFileInstaller
}

extension Data {
  fileprivate func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
