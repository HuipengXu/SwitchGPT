import Darwin
import Foundation
import SwitchGPTDesktopIntegration
import XCTest

final class RecoverySupervisorSupportTests: XCTestCase {
  func testTransactionPathMustBeDirectUUIDChild() throws {
    let root = URL(fileURLWithPath: "/private/tmp/SwitchGPT/Transactions")
    let id = UUID()
    let valid = root.appendingPathComponent(id.uuidString)

    XCTAssertEqual(
      try RecoveryTransactionPathContract.validate(candidate: valid, transactionsRoot: root),
      valid
    )
    XCTAssertThrowsError(
      try RecoveryTransactionPathContract.validate(
        candidate: root.appendingPathComponent("not-a-uuid"),
        transactionsRoot: root
      ))
    XCTAssertThrowsError(
      try RecoveryTransactionPathContract.validate(
        candidate: root.appendingPathComponent(id.uuidString).appendingPathComponent("nested"),
        transactionsRoot: root
      ))
    XCTAssertThrowsError(
      try RecoveryTransactionPathContract.validate(
        candidate: URL(fileURLWithPath: "/private/tmp/outside/\(id.uuidString)"),
        transactionsRoot: root
      ))
  }

  func testReadinessMarkerIsPrivateAndWriteOnce() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-ready-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let marker = root.appendingPathComponent("recovery.ready")

    try RecoveryReadinessMarker.create(at: marker)

    let attributes = try FileManager.default.attributesOfItem(atPath: marker.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    XCTAssertThrowsError(try RecoveryReadinessMarker.create(at: marker))
  }

  func testExistingTransactionDirectoryRequiresPrivateOwnershipAndMode() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-path-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    XCTAssertNoThrow(try RecoveryTransactionPathContract.validateExistingPrivateDirectory(root))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
    XCTAssertThrowsError(try RecoveryTransactionPathContract.validateExistingPrivateDirectory(root))
  }

  func testExistingTransactionDirectoryRejectsSymbolicLink() throws {
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-path-link-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: parent) }
    let target = parent.appendingPathComponent("target")
    let link = parent.appendingPathComponent("link")
    try FileManager.default.createDirectory(
      at: target,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    XCTAssertThrowsError(
      try RecoveryTransactionPathContract.validateExistingPrivateDirectory(link)
    )
  }

  func testUnsignedRecoveryHelperIsRejected() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("switchgpt-unsigned-helper-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let helper = root.appendingPathComponent("helper")
    try Data("fixture".utf8).write(to: helper)

    XCTAssertThrowsError(
      try EmbeddedRecoveryHelperContract.validate(
        helperURL: helper,
        expectedTeamIdentifier: "TEAMID",
        expectedSigningIdentifier: "SwitchGPTRecoverySupervisor"
      ))
  }
}
