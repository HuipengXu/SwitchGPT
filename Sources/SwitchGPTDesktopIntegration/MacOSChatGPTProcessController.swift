import AppKit
import Foundation

public final class MacOSChatGPTProcessController: DesktopProcessControlling {
  public let bundleIdentifier: String
  public let applicationURL: URL
  public let timeout: TimeInterval
  public let terminationGracePeriod: TimeInterval
  public let launchStabilityPeriod: TimeInterval

  public init(
    bundleIdentifier: String = "com.openai.codex",
    applicationURL: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app"),
    timeout: TimeInterval = 30,
    terminationGracePeriod: TimeInterval = 2,
    launchStabilityPeriod: TimeInterval = 2
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.applicationURL = applicationURL.standardizedFileURL
    self.timeout = timeout
    self.terminationGracePeriod = min(max(terminationGracePeriod, 0), timeout)
    self.launchStabilityPeriod = min(max(launchStabilityPeriod, 0), timeout)
  }

  public func isRunning() throws -> Bool {
    !NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ).isEmpty
  }

  public func terminateAndWait() throws {
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    )
    guard !running.isEmpty else { return }
    let originalProcessIdentifiers = Set(running.map(\.processIdentifier))
    for application in running {
      _ = application.terminate()
    }
    let deadline = Date().addingTimeInterval(timeout)
    let fallbackDeadline = Date().addingTimeInterval(terminationGracePeriod)
    var sentTerminationFallback = false
    while Date() < deadline {
      let remaining = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      )
      if remaining.isEmpty {
        return
      }
      if !sentTerminationFallback, Date() >= fallbackDeadline {
        for processIdentifier in Self.originalProcessesStillRunning(
          original: originalProcessIdentifiers,
          current: Set(remaining.map(\.processIdentifier))
        ) {
          _ = Darwin.kill(processIdentifier, SIGTERM)
        }
        sentTerminationFallback = true
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    throw DesktopIntegrationError.desktopDidNotTerminate
  }

  static func originalProcessesStillRunning(
    original: Set<pid_t>,
    current: Set<pid_t>
  ) -> Set<pid_t> {
    original.intersection(current)
  }

  public func launchAndWait() throws {
    guard FileManager.default.fileExists(atPath: applicationURL.path) else {
      throw DesktopIntegrationError.desktopDidNotLaunch
    }
    guard !(try isRunning()) else {
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .first?.activate(options: [.activateAllWindows])
      return
    }

    let launcher = Process()
    launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    launcher.arguments = ["-n", applicationURL.path]
    launcher.standardOutput = Pipe()
    launcher.standardError = Pipe()
    do {
      try launcher.run()
      launcher.waitUntilExit()
    } catch {
      throw DesktopIntegrationError.desktopDidNotLaunch
    }
    guard launcher.terminationStatus == 0 else {
      throw DesktopIntegrationError.desktopDidNotLaunch
    }

    let deadline = Date().addingTimeInterval(timeout)
    var observedProcessIdentifier: pid_t?
    var observedSince: Date?
    while Date() < deadline {
      let running = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      )
      if running.count == 1, let application = running.first {
        if observedProcessIdentifier != application.processIdentifier {
          observedProcessIdentifier = application.processIdentifier
          observedSince = Date()
        }
        if let observedSince,
          Date().timeIntervalSince(observedSince) >= launchStabilityPeriod
        {
          application.activate(options: [.activateAllWindows])
          return
        }
      } else {
        observedProcessIdentifier = nil
        observedSince = nil
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    throw DesktopIntegrationError.desktopDidNotLaunch
  }
}
