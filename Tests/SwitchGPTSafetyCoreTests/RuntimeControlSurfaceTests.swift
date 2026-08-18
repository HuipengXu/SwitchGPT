import Foundation
import XCTest

final class RuntimeControlSurfaceTests: XCTestCase {
  private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  func testRuntimeControlSurfacesDoNotUseRetiredSubmittedJobs() throws {
    let forbiddenCommand = "launchctl" + " submit"
    let roots = ["App", "Lifecycle", "Scripts", "Sources", "script"]
      .map(repositoryRoot.appendingPathComponent)

    for root in roots where FileManager.default.fileExists(atPath: root.path) {
      guard
        let enumerator = FileManager.default.enumerator(
          at: root,
          includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
          options: [.skipsHiddenFiles]
        )
      else {
        XCTFail("Unable to enumerate runtime control surface: \(root.path)")
        continue
      }

      for case let fileURL as URL in enumerator {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
        XCTAssertFalse(
          contents.contains(forbiddenCommand),
          "Retired submitted-job control is forbidden in runtime surfaces: \(fileURL.path)"
        )
      }
    }
  }

  func testFutureRuntimeAdaptersCannotBypassIndependentSupervisor() throws {
    let forbiddenCall = ".begin" + "Switch("
    let roots = [
      "SwitchGPTApp", "SwitchGPTAppCore", "SwitchGPTBootRecovery",
      "SwitchGPTLifecycleActivationHost", "SwitchGPTLifecycleContract",
      "SwitchGPTLifecycleHost", "SwitchGPTServiceManagementMutation",
      "SwitchGPTServiceManagementStatus",
    ]
    .map { repositoryRoot.appendingPathComponent("Sources/\($0)") }

    for root in roots where FileManager.default.fileExists(atPath: root.path) {
      guard
        let enumerator = FileManager.default.enumerator(
          at: root,
          includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
          options: [.skipsHiddenFiles]
        )
      else {
        XCTFail("Unable to enumerate runtime source: \(root.path)")
        continue
      }
      for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(
          contents.contains(forbiddenCall),
          "Runtime adapters must enter through IndependentSwitchSupervisor: \(fileURL.path)"
        )
      }
    }
  }

  func testPublicReleaseArchiveRequiresDeveloperIDVerification() throws {
    let packageScript = try String(
      contentsOf: repositoryRoot.appendingPathComponent("Scripts/package-release.sh"),
      encoding: .utf8
    )

    XCTAssertTrue(packageScript.contains("verify-release-app.sh"))
    XCTAssertTrue(packageScript.contains("--require-developer-id"))
    XCTAssertFalse(packageScript.contains("ALLOW_DEVELOPMENT"))
  }

  func testOnlyExplicitNotarizationScriptCanSubmitToApple() throws {
    let scriptsRoot = repositoryRoot.appendingPathComponent("Scripts")
    let submissionCommand = "notarytool" + " submit"
    let submittingScripts = try FileManager.default.contentsOfDirectory(
      at: scriptsRoot,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
    )
    .filter { $0.pathExtension == "sh" }
    .filter { fileURL in
      guard
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let contents = try? String(contentsOf: fileURL, encoding: .utf8)
      else { return false }
      return contents.contains(submissionCommand)
    }
    .map(\.lastPathComponent)

    XCTAssertEqual(submittingScripts, ["notarize-release.sh"])

    let notarizationScript = try String(
      contentsOf: scriptsRoot.appendingPathComponent("notarize-release.sh"),
      encoding: .utf8
    )
    let submitIndex = try XCTUnwrap(notarizationScript.range(of: submissionCommand)?.lowerBound)
    let stapleIndex = try XCTUnwrap(notarizationScript.range(of: "stapler staple")?.lowerBound)
    let gatekeeperIndex = try XCTUnwrap(notarizationScript.range(of: "spctl --assess")?.lowerBound)
    XCTAssertLessThan(submitIndex, stapleIndex)
    XCTAssertLessThan(stapleIndex, gatekeeperIndex)
  }

  func testPublicExportIncludesLinkedReleaseDocsAndExcludesPrivateContext() throws {
    let exportScript = try String(
      contentsOf: repositoryRoot.appendingPathComponent("Scripts/create-public-export.sh"),
      encoding: .utf8
    )

    XCTAssertTrue(exportScript.contains("docs/CHATGPT_UI_FOUNDATIONS.md"))
    XCTAssertTrue(exportScript.contains("docs/BRAND_RELEASE_REVIEW.md"))
    XCTAssertTrue(exportScript.contains("docs/MACOS_DISTRIBUTION.md"))
    XCTAssertFalse(exportScript.contains("\"docs/PROJECT_CONTEXT.md\""))
    XCTAssertFalse(exportScript.contains("\"outputs\""))
    XCTAssertFalse(exportScript.contains("\"work\""))
  }

  func testPublicHistoryCandidateIsIsolatedAndNeverPublishedByPreparationScript() throws {
    let preparationScript = try String(
      contentsOf: repositoryRoot.appendingPathComponent("Scripts/prepare-public-release-repo.sh"),
      encoding: .utf8
    )
    let historyAudit = try String(
      contentsOf: repositoryRoot.appendingPathComponent("Scripts/audit-public-history.sh"),
      encoding: .utf8
    )

    XCTAssertTrue(preparationScript.contains(".build/public-release-repo"))
    XCTAssertTrue(preparationScript.contains("init -q -b main"))
    XCTAssertTrue(preparationScript.contains("--single-commit"))
    XCTAssertTrue(preparationScript.contains("--require-no-remotes"))
    XCTAssertFalse(preparationScript.contains(" remote add "))
    XCTAssertFalse(preparationScript.contains(" push "))

    XCTAssertTrue(historyAudit.contains("rev-list --all"))
    XCTAssertTrue(historyAudit.contains("ls-tree -r --name-only"))
    XCTAssertTrue(historyAudit.contains("git -C \"$repository_root\" grep"))
  }

  func testDashboardUsesFixedSidebarAndDoesNotCenterToolbarWithContent() throws {
    let detail = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Views/DashboardDetailView.swift"
      ),
      encoding: .utf8
    )
    let dashboard = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Views/DashboardView.swift"
      ),
      encoding: .utf8
    )
    let style = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Support/ChatGPTStyle.swift"
      ),
      encoding: .utf8
    )
    let commands = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/App/SwitchGPTCommands.swift"
      ),
      encoding: .utf8
    )
    let confirmation = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Views/SwitchConfirmationSheet.swift"
      ),
      encoding: .utf8
    )

    XCTAssertTrue(style.contains("func chatGPTContentColumn"))
    XCTAssertTrue(style.contains("contentHorizontalInset"))
    XCTAssertTrue(detail.contains(".chatGPTContentColumn()"))
    XCTAssertFalse(detail.contains("      Divider()\n\n      ScrollView"))
    XCTAssertTrue(dashboard.contains("HStack(spacing: 0)"))
    XCTAssertTrue(dashboard.contains(".frame(width: ChatGPTStyle.sidebarWidth)"))
    XCTAssertFalse(dashboard.contains("NavigationSplitView"))
    XCTAssertTrue(commands.contains("CommandGroup(replacing: .sidebar) {}"))
    XCTAssertFalse(detail.contains("isSidebarCollapsed"))
    XCTAssertFalse(detail.contains(".chatGPTDetailContentLayout()"))
    XCTAssertFalse(detail.contains("private var safetyStatus"))
    XCTAssertFalse(detail.contains("Experimental switching is on"))
    XCTAssertTrue(confirmation.contains("SwitchGPT verifies the target account"))
  }

  func testDashboardKeepsItsCoreControlsOutOfSettings() throws {
    let app = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/App/SwitchGPTApp.swift"
      ),
      encoding: .utf8
    )
    let dashboard = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Views/DashboardView.swift"
      ),
      encoding: .utf8
    )
    let detail = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Views/DashboardDetailView.swift"
      ),
      encoding: .utf8
    )
    let menu = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Views/MenuBarView.swift"
      ),
      encoding: .utf8
    )
    let sidebar = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Views/SwitchGPTSidebar.swift"
      ),
      encoding: .utf8
    )
    let coordinator = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Support/ExperimentalRealSwitchCoordinator.swift"
      ),
      encoding: .utf8
    )
    let confirmation = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Views/SwitchConfirmationSheet.swift"
      ),
      encoding: .utf8
    )
    let menuConfirmation = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/SwitchGPTApp/Support/MenuBarSwitchConfirmation.swift"
      ),
      encoding: .utf8
    )

    XCTAssertTrue(app.contains("Window(\"SwitchGPT\", id: \"dashboard\")"))
    XCTAssertTrue(app.contains(".defaultSize(width: 820, height: 592)"))
    XCTAssertTrue(menu.contains("openWindow(id: \"dashboard\")"))
    XCTAssertFalse(app.contains("Settings {"))
    XCTAssertFalse(menu.contains("SettingsLink"))
    XCTAssertFalse(sidebar.contains("SettingsLink"))
    XCTAssertFalse(dashboard.contains("experimentalRealSwitchingEnabled"))
    XCTAssertFalse(menu.contains("experimentalRealSwitchingEnabled"))
    XCTAssertTrue(dashboard.contains("RealSwitchWorkflow.prepare"))
    XCTAssertTrue(dashboard.contains("UsageRefreshPolicy.dashboardVisibleMaxAge"))
    XCTAssertTrue(menu.contains("UsageRefreshPolicy.menuOpenMaxAge"))
    XCTAssertTrue(menu.contains("UsageRefreshPolicy.backgroundInterval"))
    XCTAssertTrue(detail.contains("isRefreshing"))
    XCTAssertTrue(detail.contains("RefreshFeedback"))
    XCTAssertTrue(detail.contains("Task.sleep(for: .milliseconds(120))"))
    XCTAssertTrue(detail.contains("Refresh failed"))
    XCTAssertFalse(coordinator.contains("unsupportedTargetApplicationVersion"))
    XCTAssertTrue(
      coordinator.contains(
        "let targetApplicationCompatibility = try validateTargetApplication()"
      )
    )
    XCTAssertTrue(
      coordinator.contains(
        "try validateTargetApplication() == plan.targetApplicationCompatibility"
      )
    )
    XCTAssertTrue(
      dashboard.contains(
        "showsUnvalidatedVersionWarning: !plan.targetApplicationCompatibility.isValidated"
      )
    )
    XCTAssertTrue(confirmation.contains("SwitchGPT will still try this switch"))
    XCTAssertTrue(confirmation.contains("one recovery launch"))
    XCTAssertTrue(
      menu.contains(
        "hasUnvalidatedChatGPTVersion: !plan.targetApplicationCompatibility.isValidated"
      )
    )
    XCTAssertTrue(menuConfirmation.contains("SwitchGPT will still try this switch"))
  }
}
