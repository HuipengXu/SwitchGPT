import Foundation
import SwitchGPTLifecycleContract
import XCTest

final class LaunchAgentContractTests: XCTestCase {
  private let repositoryPlistURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Lifecycle/LaunchAgents/com.switchgpt.recovery-at-login.plist")

  func testRepositoryLaunchAgentMatchesCanonicalContract() throws {
    let data = try Data(contentsOf: repositoryPlistURL)
    XCTAssertNoThrow(try LaunchAgentContract.validate(data: data))

    let canonical = try LaunchAgentContract.canonicalPropertyListData(format: .xml)
    XCTAssertEqual(
      try dictionary(from: data) as NSDictionary, try dictionary(from: canonical) as NSDictionary)
  }

  func testCanonicalBinaryPropertyListIsAccepted() throws {
    let data = try LaunchAgentContract.canonicalPropertyListData(format: .binary)
    XCTAssertNoThrow(try LaunchAgentContract.validate(data: data))
  }

  func testMalformedPropertyListIsRejected() {
    XCTAssertThrowsError(try LaunchAgentContract.validate(data: Data("not a plist".utf8))) {
      XCTAssertEqual($0 as? LaunchAgentContractError, .malformedPropertyList)
    }
  }

  func testKeepAliveIsRejectedEvenWhenFalse() throws {
    try assertRejected(extraKey: "KeepAlive", value: false)
  }

  func testSuccessfulExitRestartPolicyIsRejected() throws {
    try assertRejected(extraKey: "KeepAlive", value: ["SuccessfulExit": false])
  }

  func testTimersAndCalendarTriggersAreRejected() throws {
    try assertRejected(extraKey: "StartInterval", value: 60)
    try assertRejected(extraKey: "StartCalendarInterval", value: ["Minute": 0])
  }

  func testFilesystemTriggersAreRejected() throws {
    try assertRejected(extraKey: "WatchPaths", value: ["/tmp"])
    try assertRejected(extraKey: "QueueDirectories", value: ["/tmp"])
  }

  func testIPCAndNetworkTriggersAreRejected() throws {
    try assertRejected(extraKey: "MachServices", value: ["com.switchgpt.recovery": true])
    try assertRejected(extraKey: "Sockets", value: ["Listener": ["SockServiceName": "9999"]])
  }

  func testExternalProgramAndLegacyProgramKeysAreRejected() throws {
    var dictionary = try canonicalDictionary()
    dictionary["BundleProgram"] = "/tmp/SwitchGPTBootRecovery"
    try assertRejected(dictionary, expected: .invalidBundleProgram)

    try assertRejected(extraKey: "Program", value: "/tmp/SwitchGPTBootRecovery")
  }

  func testExtraArgumentsAndWrongCommandAreRejected() throws {
    var extra = try canonicalDictionary()
    extra["ProgramArguments"] = LaunchAgentContract.programArguments + ["account-b"]
    try assertRejected(extra, expected: .invalidProgramArguments)

    var wrong = try canonicalDictionary()
    wrong["ProgramArguments"] = ["SwitchGPTBootRecovery", "begin-switch"]
    try assertRejected(wrong, expected: .invalidProgramArguments)
  }

  func testRunAtLoadAndLaunchOnlyOnceMustBeBooleanTrue() throws {
    var runAtLoadFalse = try canonicalDictionary()
    runAtLoadFalse["RunAtLoad"] = false
    try assertRejected(runAtLoadFalse, expected: .runAtLoadRequired)

    var runAtLoadInteger = try canonicalDictionary()
    runAtLoadInteger["RunAtLoad"] = 1
    try assertRejected(runAtLoadInteger, expected: .runAtLoadRequired)

    var launchOnceFalse = try canonicalDictionary()
    launchOnceFalse["LaunchOnlyOnce"] = false
    try assertRejected(launchOnceFalse, expected: .launchOnlyOnceRequired)

    var launchOnceInteger = try canonicalDictionary()
    launchOnceInteger["LaunchOnlyOnce"] = 1
    try assertRejected(launchOnceInteger, expected: .launchOnlyOnceRequired)
  }

  func testSessionMustBeAqua() throws {
    var background = try canonicalDictionary()
    background["LimitLoadToSessionType"] = "Background"
    try assertRejected(background, expected: .invalidSessionType)
  }

  private func assertRejected(extraKey: String, value: Any) throws {
    var dictionary = try canonicalDictionary()
    dictionary[extraKey] = value
    try assertRejected(dictionary, expected: .unexpectedKeys)
  }

  private func assertRejected(
    _ dictionary: [String: Any],
    expected: LaunchAgentContractError
  ) throws {
    let data = try PropertyListSerialization.data(
      fromPropertyList: dictionary,
      format: .binary,
      options: 0
    )
    XCTAssertThrowsError(try LaunchAgentContract.validate(data: data)) {
      XCTAssertEqual($0 as? LaunchAgentContractError, expected)
    }
  }

  private func canonicalDictionary() throws -> [String: Any] {
    try dictionary(
      from: LaunchAgentContract.canonicalPropertyListData(format: .binary)
    )
  }

  private func dictionary(from data: Data) throws -> [String: Any] {
    try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as? [String: Any]
    )
  }
}
