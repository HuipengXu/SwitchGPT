import Darwin
import Foundation
import SwitchGPTLifecycleContract
import XCTest

final class LifecycleBundleContractTests: XCTestCase {
  private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  func testRepositoryInfoPropertyListMatchesCanonicalContract() throws {
    let repositoryInfo = repositoryRoot.appendingPathComponent("Lifecycle/App/Info.plist")
    let data = try Data(contentsOf: repositoryInfo)
    XCTAssertNoThrow(try LifecycleBundleContract.validateInfo(data: data))

    let canonical = try LifecycleBundleContract.canonicalInfoPropertyListData(format: .xml)
    XCTAssertEqual(
      try dictionary(from: data) as NSDictionary,
      try dictionary(from: canonical) as NSDictionary
    )
  }

  func testCanonicalUnsignedBundleIsAccepted() throws {
    let fixture = try makeBundleFixture(includeCodeSignatureDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    XCTAssertNoThrow(try LifecycleBundleContract.validate(bundleURL: fixture.bundle))
  }

  func testUnexpectedBundleContentIsRejected() throws {
    let fixture = try makeBundleFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try Data().write(to: fixture.bundle.appendingPathComponent("Contents/unexpected"))

    XCTAssertThrowsError(try LifecycleBundleContract.validate(bundleURL: fixture.bundle)) {
      XCTAssertEqual(
        $0 as? LifecycleBundleContractError,
        .unexpectedDirectoryContents("Contents")
      )
    }
  }

  func testRecoveryExecutableSymbolicLinkIsRejected() throws {
    let fixture = try makeBundleFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recovery = fixture.bundle.appendingPathComponent(
      "Contents/Library/LaunchServices/\(LifecycleBundleContract.recoveryExecutableName)"
    )
    try FileManager.default.removeItem(at: recovery)
    let external = fixture.root.appendingPathComponent("external-recovery")
    try Data("fixture".utf8).write(to: external)
    try FileManager.default.createSymbolicLink(at: recovery, withDestinationURL: external)

    XCTAssertThrowsError(try LifecycleBundleContract.validate(bundleURL: fixture.bundle)) {
      XCTAssertEqual(
        $0 as? LifecycleBundleContractError,
        .unsafeFileSystemObject("Contents/Library/LaunchServices/recovery")
      )
    }
  }

  func testDangerousLaunchAgentKeyIsRejectedInsideBundle() throws {
    let fixture = try makeBundleFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let launchAgent = fixture.bundle.appendingPathComponent(
      "Contents/Library/LaunchAgents/\(LifecycleBundleContract.launchAgentFileName)"
    )
    var dictionary = try dictionary(from: Data(contentsOf: launchAgent))
    dictionary["KeepAlive"] = false
    try PropertyListSerialization.data(
      fromPropertyList: dictionary,
      format: .xml,
      options: 0
    ).write(to: launchAgent)

    XCTAssertThrowsError(try LifecycleBundleContract.validate(bundleURL: fixture.bundle)) {
      XCTAssertEqual($0 as? LifecycleBundleContractError, .invalidLaunchAgent)
    }
  }

  func testWrongHostExecutableNameIsRejected() throws {
    let data = try LifecycleBundleContract.canonicalInfoPropertyListData(format: .binary)
    var dictionary = try dictionary(from: data)
    dictionary["CFBundleExecutable"] = "UnexpectedHost"
    let modified = try PropertyListSerialization.data(
      fromPropertyList: dictionary,
      format: .binary,
      options: 0
    )

    XCTAssertThrowsError(try LifecycleBundleContract.validateInfo(data: modified)) {
      XCTAssertEqual(
        $0 as? LifecycleBundleContractError,
        .invalidInfoValue("CFBundleExecutable")
      )
    }
  }

  private func makeBundleFixture(includeCodeSignatureDirectory: Bool = false) throws -> (
    root: URL, bundle: URL
  ) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "switchgpt-lifecycle-contract-\(UUID().uuidString)",
      isDirectory: true
    )
    let bundle = root.appendingPathComponent("SwitchGPTLifecycleValidation.app", isDirectory: true)
    let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
    let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
    let launchAgents = contents.appendingPathComponent(
      "Library/LaunchAgents",
      isDirectory: true
    )
    let launchServices = contents.appendingPathComponent(
      "Library/LaunchServices",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: launchServices, withIntermediateDirectories: true)
    if includeCodeSignatureDirectory {
      try FileManager.default.createDirectory(
        at: contents.appendingPathComponent("_CodeSignature", isDirectory: true),
        withIntermediateDirectories: false
      )
    }

    try LifecycleBundleContract.canonicalInfoPropertyListData(format: .xml)
      .write(to: contents.appendingPathComponent("Info.plist"))
    try LaunchAgentContract.canonicalPropertyListData(format: .xml)
      .write(to: launchAgents.appendingPathComponent(LifecycleBundleContract.launchAgentFileName))
    try writeExecutable(
      at: macOS.appendingPathComponent(LifecycleBundleContract.hostExecutableName)
    )
    try writeExecutable(
      at: launchServices.appendingPathComponent(LifecycleBundleContract.recoveryExecutableName)
    )
    return (root, bundle)
  }

  private func writeExecutable(at url: URL) throws {
    try Data("fixture".utf8).write(to: url)
    guard url.path.withCString({ chmod($0, 0o755) }) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private func dictionary(from data: Data) throws -> [String: Any] {
    try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as? [String: Any]
    )
  }
}
