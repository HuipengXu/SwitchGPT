import Darwin
import Foundation
import XCTest

@testable import SwitchGPTLifecycleContract

final class RebootDeliveryEvidenceStoreTests: XCTestCase {
  private let firstBoot = BootSessionIdentifier(rawValue: "100-1")!
  private let secondBoot = BootSessionIdentifier(rawValue: "200-2")!
  private let thirdBoot = BootSessionIdentifier(rawValue: "300-3")!

  func testBootSessionIdentifierRejectsMalformedValuesAndSystemValueIsValid() throws {
    XCTAssertNil(BootSessionIdentifier(rawValue: ""))
    XCTAssertNil(BootSessionIdentifier(rawValue: "1"))
    XCTAssertNil(BootSessionIdentifier(rawValue: "1--2"))
    XCTAssertNil(BootSessionIdentifier(rawValue: "-1-2"))
    XCTAssertNil(BootSessionIdentifier(rawValue: "one-2"))
    XCTAssertNotNil(try SystemBootSessionIdentifier.current())
  }

  func testArmingDoesNotCountSameBootAsRebootDelivery() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    XCTAssertEqual(try fixture.store.status(on: firstBoot), .notArmed)
    XCTAssertTrue(try fixture.store.arm(on: firstBoot))
    XCTAssertFalse(try fixture.store.arm(on: firstBoot))
    XCTAssertEqual(try fixture.store.status(on: firstBoot), .armedOnCurrentBoot)
    XCTAssertEqual(
      try fixture.store.recordDelivery(on: firstBoot),
      .armedForFutureBoot
    )
    XCTAssertEqual(try fixture.store.status(on: firstBoot), .armedOnCurrentBoot)
  }

  func testNewBootRecordsOnceAndSecondDeliveryIsDurableViolation() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    XCTAssertTrue(try fixture.recorder.reserve(.registration))
    XCTAssertTrue(try fixture.store.arm(on: firstBoot))

    XCTAssertEqual(
      RebootDeliveryEntry.run(
        recorder: fixture.recorder,
        evidenceStore: fixture.store,
        bootSession: secondBoot
      ),
      .rebootDeliveryRecorded
    )
    XCTAssertEqual(try fixture.store.status(on: secondBoot), .deliveredOnCurrentBoot)

    XCTAssertEqual(
      RebootDeliveryEntry.run(
        recorder: fixture.recorder,
        evidenceStore: fixture.store,
        bootSession: secondBoot
      ),
      .duplicateDeliveryDetected
    )
    XCTAssertEqual(try fixture.store.status(on: secondBoot), .duplicateDeliveryDetected)
  }

  func testDifferentLaterBootFailsClosedWithoutReplacingEvidence() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    XCTAssertTrue(try fixture.store.arm(on: firstBoot))
    XCTAssertEqual(
      try fixture.store.recordDelivery(on: secondBoot),
      .rebootDeliveryRecorded
    )
    XCTAssertEqual(try fixture.store.status(on: thirdBoot), .deliveredOnPriorBoot)
    XCTAssertThrowsError(try fixture.store.recordDelivery(on: thirdBoot)) {
      XCTAssertEqual($0 as? RebootDeliveryEvidenceError, .unsafeStorage)
    }
    XCTAssertEqual(try fixture.store.status(on: secondBoot), .deliveredOnCurrentBoot)
  }

  func testEntryRequiresDurableRegistrationOwnership() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    XCTAssertTrue(try fixture.store.arm(on: firstBoot))

    XCTAssertEqual(
      RebootDeliveryEntry.run(
        recorder: fixture.recorder,
        evidenceStore: fixture.store,
        bootSession: secondBoot
      ),
      .unsafeState
    )
    XCTAssertEqual(
      try fixture.store.status(on: secondBoot),
      .rebootOccurredWithoutDelivery
    )
  }

  func testRebootControllerArmsBeforeRegistrationAndLeavesEnabledService() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = RebootFixtureService(statuses: [.notRegistered, .enabled])
    let controller = RebootLifecycleValidationController(
      activationController: LifecycleActivationController(
        service: service,
        attemptRecorder: fixture.recorder,
        preflight: RebootFixturePreflight()
      ),
      evidenceStore: fixture.store,
      bootSession: firstBoot
    )

    let report = controller.prepareForReboot()
    XCTAssertEqual(report.registration, .registeredEnabled)
    XCTAssertNil(report.cleanup)
    XCTAssertEqual(report.evidenceStatus, .armedOnCurrentBoot)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(service.unregisterCount, 0)
  }

  func testRebootControllerCleansApprovalOrAmbiguousRegistrationOnce() throws {
    for statuses in [
      [
        RecoveryServiceStatus.notRegistered,
        .requiresApproval,
        .requiresApproval,
        .notRegistered,
      ],
      [.notRegistered, .notFound, .notFound, .notRegistered],
    ] {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let service = RebootFixtureService(statuses: statuses)
      let report = RebootLifecycleValidationController(
        activationController: LifecycleActivationController(
          service: service,
          attemptRecorder: fixture.recorder,
          preflight: RebootFixturePreflight()
        ),
        evidenceStore: fixture.store,
        bootSession: firstBoot
      ).prepareForReboot()

      XCTAssertTrue(
        report.registration == .registeredAwaitingApproval
          || report.registration == .registrationUnconfirmed
      )
      XCTAssertEqual(report.cleanup, .unregistered)
      XCTAssertEqual(service.registerCount, 1)
      XCTAssertEqual(service.unregisterCount, 1)
    }
  }

  func testCorruptedOrSymbolicLinkEvidenceFailsClosed() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    XCTAssertTrue(try fixture.store.arm(on: firstBoot))
    let armedURL = fixture.store.directoryURL.appendingPathComponent(
      "armed-boot.identifier"
    )
    try Data("corrupt\n".utf8).write(to: armedURL)
    XCTAssertEqual(armedURL.path.withCString { chmod($0, 0o600) }, 0)
    XCTAssertThrowsError(try fixture.store.status(on: firstBoot)) {
      XCTAssertEqual($0 as? RebootDeliveryEvidenceError, .unsafeStorage)
    }

    try FileManager.default.removeItem(at: armedURL)
    try FileManager.default.createSymbolicLink(
      at: armedURL,
      withDestinationURL: fixture.root.appendingPathComponent("attacker")
    )
    XCTAssertThrowsError(try fixture.store.status(on: firstBoot)) {
      XCTAssertEqual($0 as? RebootDeliveryEvidenceError, .unsafeStorage)
    }
  }

  func testEvidenceUsesPrivateWriteOnceFiles() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    XCTAssertTrue(try fixture.store.arm(on: firstBoot))
    XCTAssertEqual(
      try fixture.store.recordDelivery(on: secondBoot),
      .rebootDeliveryRecorded
    )

    let directoryStatus = try status(at: fixture.store.directoryURL)
    XCTAssertEqual(directoryStatus.st_mode & 0o777, 0o700)
    for name in ["armed-boot.identifier", "delivered-boot.identifier"] {
      let fileStatus = try status(
        at: fixture.store.directoryURL.appendingPathComponent(name)
      )
      XCTAssertEqual(fileStatus.st_mode & S_IFMT, S_IFREG)
      XCTAssertEqual(fileStatus.st_mode & 0o777, 0o600)
      XCTAssertEqual(fileStatus.st_uid, geteuid())
      XCTAssertEqual(fileStatus.st_nlink, 1)
    }
  }

  private func makeFixture() throws -> (
    root: URL,
    recorder: PersistentActivationAttemptRecorder,
    store: RebootDeliveryEvidenceStore
  ) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "switchgpt-safety-reboot-evidence-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    XCTAssertEqual(root.path.withCString { chmod($0, 0o700) }, 0)
    let recorder = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .rebootLifecycle
    )
    return (
      root,
      recorder,
      try RebootDeliveryEvidenceStore(sessionURL: recorder.sessionURL)
    )
  }

  private func status(at url: URL) throws -> stat {
    var value = stat()
    guard url.path.withCString({ lstat($0, &value) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return value
  }
}

private final class RebootFixtureService: RecoveryServiceControlling {
  private let statuses: [RecoveryServiceStatus]
  private var index = 0
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  init(statuses: [RecoveryServiceStatus]) {
    self.statuses = statuses
  }

  func readStatus() throws -> RecoveryServiceStatus {
    defer { index += 1 }
    return statuses[min(index, statuses.count - 1)]
  }

  func register() throws {
    registerCount += 1
  }

  func unregister() throws {
    unregisterCount += 1
  }
}

private struct RebootFixturePreflight: LifecycleActivationPreflighting {
  func validateForRegistration() throws {}
}
