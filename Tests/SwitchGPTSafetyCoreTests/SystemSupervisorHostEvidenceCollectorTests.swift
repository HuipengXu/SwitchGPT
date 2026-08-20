import Foundation
import XCTest

@testable import SwitchGPTSafetyCore

final class SystemSupervisorHostEvidenceCollectorTests: XCTestCase {
  func testSnapshotMapsToStrictHostEvidence() throws {
    let snapshot = SupervisorRuntimeSnapshot(
      bundleIdentifier: "com.kunpeng.SwitchGPT",
      bundleURL: URL(fileURLWithPath: "/Applications/SwitchGPT.app"),
      executableURL: URL(fileURLWithPath: "/Applications/SwitchGPT.app/Contents/MacOS/SwitchGPT"),
      signatureEvidence: .verified(
        teamIdentifier: "6HX53HCVG5",
        signingIdentifier: "com.kunpeng.SwitchGPT"
      ),
      ancestorExecutableURLs: [URL(fileURLWithPath: "/sbin/launchd")]
    )
    let configuration = SupervisorHostConfiguration(
      expectedHostBundleIdentifier: "com.kunpeng.SwitchGPT",
      expectedHostTeamIdentifier: "6HX53HCVG5",
      targetBundleIdentifier: "com.openai.codex",
      targetBundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app")
    )

    let evidence = SystemSupervisorHostEvidenceCollector.evidence(
      from: snapshot,
      configuration: configuration
    )

    XCTAssertNoThrow(try IndependentSupervisorHostContract.validateInteractiveSwitch(evidence))
    XCTAssertEqual(evidence.launchMechanism, .application)
    XCTAssertEqual(evidence.ancestorExecutableURLs, snapshot.ancestorExecutableURLs)
  }

  func testSnapshotFromChatGPTAncestorFailsContract() {
    let snapshot = SupervisorRuntimeSnapshot(
      bundleIdentifier: "com.kunpeng.SwitchGPT",
      bundleURL: URL(fileURLWithPath: "/Applications/SwitchGPT.app"),
      executableURL: URL(fileURLWithPath: "/Applications/SwitchGPT.app/Contents/MacOS/SwitchGPT"),
      signatureEvidence: .verified(
        teamIdentifier: "6HX53HCVG5",
        signingIdentifier: "com.kunpeng.SwitchGPT"
      ),
      ancestorExecutableURLs: [
        URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT")
      ]
    )
    let configuration = SupervisorHostConfiguration(
      expectedHostBundleIdentifier: "com.kunpeng.SwitchGPT",
      expectedHostTeamIdentifier: "6HX53HCVG5",
      targetBundleIdentifier: "com.openai.codex",
      targetBundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app")
    )
    let evidence = SystemSupervisorHostEvidenceCollector.evidence(
      from: snapshot,
      configuration: configuration
    )

    XCTAssertThrowsError(
      try IndependentSupervisorHostContract.validateInteractiveSwitch(evidence)
    ) { error in
      XCTAssertEqual(error as? SupervisorSafetyError, .targetHostedAncestor)
    }
  }
}
