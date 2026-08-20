import AppKit
import SwiftUI
import SwitchGPTAppCore

final class SwitchGPTAppDelegate: NSObject, NSApplicationDelegate {
  private let logger = LoggerBridge.lifecycle

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    logger.info("SwitchGPT UI launched in read-only quota mode")
  }
}

@main
struct SwitchGPTApp: App {
  @NSApplicationDelegateAdaptor(SwitchGPTAppDelegate.self) private var appDelegate
  @State private var store = SwitchGPTAppStore(
    persistence: PreviewStateFileStore.defaultStore,
    initialAccounts: []
  )

  var body: some Scene {
    Window("SwitchGPT", id: "dashboard") {
      DashboardView(store: store)
    }
    .defaultSize(width: 820, height: 592)
    .windowStyle(.hiddenTitleBar)
    .commands {
      SwitchGPTCommands(store: store)
    }

    MenuBarExtra {
      MenuBarView(store: store)
    } label: {
      MenuBarLabel(store: store)
    }
    .menuBarExtraStyle(.window)
  }
}

private enum LoggerBridge {
  static let lifecycle = OSLogProxy(subsystem: "com.kunpeng.switchgpt", category: "lifecycle")
}

private struct OSLogProxy {
  let subsystem: String
  let category: String

  func info(_ message: String) {
    NSLog("[%@/%@] %@", subsystem, category, message)
  }
}
