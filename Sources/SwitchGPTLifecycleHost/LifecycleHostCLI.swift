import AppKit
import Darwin
import Foundation
import OSLog
import SwitchGPTLifecycleContract
import SwitchGPTServiceManagementStatus

@main
@MainActor
enum LifecycleHostCLI {
  private static let logger = Logger(
    subsystem: LifecycleBundleContract.bundleIdentifier,
    category: "LifecycleHost"
  )

  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["service-status"] {
      runServiceStatusApplication()
    }
    if arguments == ["registration-preflight"] {
      do {
        try RecoveryAgentRegistrationPreflight(bundleURL: enclosingBundleURL())
          .validateForRegistration()
        write(outcome: "ready")
        exit(0)
      } catch {
        write(outcome: "notReady")
        exit(1)
      }
    }
    guard arguments == ["validate-bundle"] else {
      write(outcome: "invalidInvocation")
      exit(64)
    }

    do {
      try LifecycleBundleContract.validate(bundleURL: enclosingBundleURL())
      write(outcome: "valid")
      exit(0)
    } catch {
      write(outcome: "invalidBundle")
      exit(1)
    }
  }

  private static func enclosingBundleURL() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0])
      .standardizedFileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func runServiceStatusApplication() -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    DispatchQueue.main.async {
      let status = RecoveryAgentStatusReader.read().rawValue
      logger.notice("serviceStatus=\(status, privacy: .public)")
      write(outcome: status)
      application.terminate(nil)
    }
    application.run()
    exit(0)
  }

  private static func write(outcome: String) {
    FileHandle.standardOutput.write(Data("{\"outcome\":\"\(outcome)\"}\n".utf8))
  }
}
