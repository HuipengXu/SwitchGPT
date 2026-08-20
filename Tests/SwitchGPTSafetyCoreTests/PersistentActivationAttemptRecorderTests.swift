import Darwin
import Foundation
import XCTest

@testable import SwitchGPTLifecycleContract
@testable import SwitchGPTSafetyCore

final class PersistentActivationAttemptRecorderTests: XCTestCase {
  func testReservationsPersistWhenSessionIsReopened() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .immediateLifecycle
    )
    XCTAssertTrue(try first.reserve(.registration))
    XCTAssertTrue(try first.reserve(.unregistration))

    let reopened = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .immediateLifecycle
    )
    XCTAssertFalse(try reopened.reserve(.registration))
    XCTAssertFalse(try reopened.reserve(.unregistration))
    XCTAssertTrue(try reopened.hasReservation(.registration))
    XCTAssertTrue(try reopened.hasReservation(.unregistration))
  }

  func testMissingReservationIsReportedWithoutCreatingIt() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .immediateLifecycle
    )

    XCTAssertFalse(try recorder.hasReservation(.registration))
    XCTAssertTrue(try recorder.reserve(.registration))
  }

  func testCorruptedReservationIsRejected() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .immediateLifecycle
    )
    XCTAssertTrue(try recorder.reserve(.registration))
    let reservation = recorder.directoryURL.appendingPathComponent(
      "registration.reserved"
    )
    try Data("corrupt\n".utf8).write(to: reservation)
    XCTAssertEqual(reservation.path.withCString { chmod($0, 0o600) }, 0)

    XCTAssertThrowsError(try recorder.hasReservation(.registration)) {
      XCTAssertEqual(
        $0 as? PersistentActivationAttemptRecorderError,
        .unsafeStorage
      )
    }
  }

  func testDifferentSessionsHaveIndependentBudgets() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let first = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .immediateLifecycle
    )
    let second = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .rebootLifecycle
    )

    XCTAssertTrue(try first.reserve(.registration))
    XCTAssertTrue(try second.reserve(.registration))
    XCTAssertFalse(try first.reserve(.registration))
    XCTAssertFalse(try second.reserve(.registration))
  }

  func testSessionLockRejectsConcurrentLifecycleOperationAndCanBeReacquired() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .immediateLifecycle
    )
    let first = try LifecycleActivationSessionLock(sessionURL: recorder.sessionURL)

    XCTAssertThrowsError(
      try LifecycleActivationSessionLock(sessionURL: recorder.sessionURL)
    ) {
      XCTAssertEqual($0 as? SafetyError, .lockUnavailable)
    }

    first.release()
    let reacquired = try LifecycleActivationSessionLock(sessionURL: recorder.sessionURL)
    reacquired.release()
  }

  func testStorageUsesPrivateDirectoriesAndFiles() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .upgradeLifecycle
    )
    XCTAssertTrue(try recorder.reserve(.registration))

    for directory in sessionAncestors(for: recorder, root: root) {
      let status = try fileStatus(at: directory)
      XCTAssertEqual(status.st_mode & S_IFMT, S_IFDIR)
      XCTAssertEqual(status.st_mode & 0o777, 0o700)
      XCTAssertEqual(status.st_uid, geteuid())
    }

    let reservation = recorder.directoryURL.appendingPathComponent(
      "registration.reserved"
    )
    let status = try fileStatus(at: reservation)
    XCTAssertEqual(status.st_mode & S_IFMT, S_IFREG)
    XCTAssertEqual(status.st_mode & 0o777, 0o600)
    XCTAssertEqual(status.st_uid, geteuid())
    XCTAssertEqual(status.st_nlink, 1)
  }

  func testBroadFixtureRootIsRejected() throws {
    let root = try makeRoot(mode: 0o755)
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertThrowsError(
      try PersistentActivationAttemptRecorder(
        testRootURL: root,
        session: .immediateLifecycle
      )
    ) {
      XCTAssertEqual(
        $0 as? PersistentActivationAttemptRecorderError,
        .unsafeStorage
      )
    }
  }

  func testNonFixtureRootIsRejected() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "unrelated-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    XCTAssertEqual(root.path.withCString { chmod($0, 0o700) }, 0)
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertThrowsError(
      try PersistentActivationAttemptRecorder(
        testRootURL: root,
        session: .immediateLifecycle
      )
    ) {
      XCTAssertEqual(
        $0 as? PersistentActivationAttemptRecorderError,
        .unsafeRoot
      )
    }
  }

  func testReservationSymlinkIsRejectedWhenSessionIsReopened() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .immediateLifecycle
    )
    let reservation = recorder.directoryURL.appendingPathComponent(
      "registration.reserved"
    )
    try FileManager.default.createSymbolicLink(
      at: reservation,
      withDestinationURL: root.appendingPathComponent("attacker-marker")
    )

    let reopened = try PersistentActivationAttemptRecorder(
      testRootURL: root,
      session: .immediateLifecycle
    )
    XCTAssertThrowsError(try reopened.reserve(.registration)) {
      XCTAssertEqual(
        $0 as? PersistentActivationAttemptRecorderError,
        .unsafeStorage
      )
    }
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("attacker-marker").path
      )
    )
  }

  private func sessionAncestors(
    for recorder: PersistentActivationAttemptRecorder,
    root: URL
  ) -> [URL] {
    let applicationDirectory = root.appendingPathComponent(
      "persistent-activation-validation",
      isDirectory: true
    )
    let validationDirectory = applicationDirectory.appendingPathComponent(
      "system-activation",
      isDirectory: true
    )
    let sessionsDirectory = validationDirectory.appendingPathComponent(
      "sessions",
      isDirectory: true
    )
    return [
      applicationDirectory,
      validationDirectory,
      sessionsDirectory,
      recorder.sessionURL,
      recorder.directoryURL,
    ]
  }

  private func makeRoot(mode: mode_t = 0o700) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "switchgpt-safety-persistent-activation-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    guard root.path.withCString({ chmod($0, mode) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return root
  }

  private func fileStatus(at url: URL) throws -> stat {
    var status = stat()
    guard url.path.withCString({ lstat($0, &status) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return status
  }
}
