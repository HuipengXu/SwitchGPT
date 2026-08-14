import Darwin
import Foundation
import XCTest

@testable import SwitchGPTLifecycleContract

final class LifecycleActivationInstallContractTests: XCTestCase {
  func testExactPrivateOwnedBundleDirectoryIsAccepted() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let bundle = root.appendingPathComponent("SwitchGPTLifecycleValidation.app")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: false)

    XCTAssertNoThrow(
      try LifecycleActivationInstallContract.validate(
        bundleURL: bundle,
        expectedBundleURL: bundle
      )
    )
  }

  func testUnexpectedPathAndSymbolicLinkAreRejected() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let expected = root.appendingPathComponent("Expected.app")
    let actual = root.appendingPathComponent("Actual.app")
    try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false)

    XCTAssertThrowsError(
      try LifecycleActivationInstallContract.validate(
        bundleURL: actual,
        expectedBundleURL: expected
      )
    ) {
      XCTAssertEqual(
        $0 as? LifecycleActivationInstallContractError,
        .invalidInstallLocation
      )
    }

    try FileManager.default.createSymbolicLink(at: expected, withDestinationURL: actual)
    XCTAssertThrowsError(
      try LifecycleActivationInstallContract.validate(
        bundleURL: expected,
        expectedBundleURL: expected
      )
    ) {
      XCTAssertEqual(
        $0 as? LifecycleActivationInstallContractError,
        .unsafeInstallLocation
      )
    }
  }

  private func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "switchgpt-safety-activation-install-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    guard root.path.withCString({ chmod($0, 0o700) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return root
  }
}
