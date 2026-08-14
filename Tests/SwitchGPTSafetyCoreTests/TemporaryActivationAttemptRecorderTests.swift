import Darwin
import Foundation
import SwitchGPTLifecycleContract
import XCTest

final class TemporaryActivationAttemptRecorderTests: XCTestCase {
  func testReservationPersistsAcrossRecorderInstances() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertTrue(
      try TemporaryActivationAttemptRecorder(rootURL: root).reserve(.registration)
    )
    XCTAssertFalse(
      try TemporaryActivationAttemptRecorder(rootURL: root).reserve(.registration)
    )

    let reservation = root.appendingPathComponent(
      "activation-attempts/registration.reserved"
    )
    var status = stat()
    XCTAssertEqual(reservation.path.withCString { lstat($0, &status) }, 0)
    XCTAssertEqual(status.st_mode & 0o777, 0o600)
    XCTAssertEqual(status.st_nlink, 1)
  }

  func testRegistrationAndUnregistrationHaveIndependentBudgets() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = try TemporaryActivationAttemptRecorder(rootURL: root)

    XCTAssertTrue(try recorder.reserve(.registration))
    XCTAssertTrue(try recorder.reserve(.unregistration))
    XCTAssertFalse(try recorder.reserve(.registration))
    XCTAssertFalse(try recorder.reserve(.unregistration))
  }

  func testBroadRootPermissionsAreRejected() throws {
    let root = try makeRoot(mode: 0o755)
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertThrowsError(try TemporaryActivationAttemptRecorder(rootURL: root)) {
      XCTAssertEqual(
        $0 as? TemporaryActivationAttemptRecorderError,
        .unsafeStorage
      )
    }
  }

  func testSymbolicLinkAttemptDirectoryIsRejected() throws {
    let root = try makeRoot()
    let target = try makeRoot()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: target)
    }
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("activation-attempts"),
      withDestinationURL: target
    )

    XCTAssertThrowsError(try TemporaryActivationAttemptRecorder(rootURL: root)) {
      XCTAssertEqual(
        $0 as? TemporaryActivationAttemptRecorderError,
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

    XCTAssertThrowsError(try TemporaryActivationAttemptRecorder(rootURL: root)) {
      XCTAssertEqual(
        $0 as? TemporaryActivationAttemptRecorderError,
        .unsafeRoot
      )
    }
  }

  private func makeRoot(mode: mode_t = 0o700) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "switchgpt-safety-activation-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    guard root.path.withCString({ chmod($0, mode) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return root
  }
}
