import AppKit
import SwiftUI
import SwitchGPTAppCore

final class SwitchGPTAppDelegate: NSObject, NSApplicationDelegate {
  private let logger = LoggerBridge.lifecycle

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    logger.info("SwitchGPT UI launched in read-only simulation mode")
  }
}

@main
struct SwitchGPTApp: App {
  @NSApplicationDelegateAdaptor(SwitchGPTAppDelegate.self) private var appDelegate
  @State private var store = SwitchGPTAppStore(
    persistence: PreviewStateFileStore.defaultStore
  )

  var body: some Scene {
    Window("SwitchGPT", id: "main") {
      DashboardView(store: store)
    }
    .defaultSize(width: 980, height: 680)
    .commands {
      SwitchGPTCommands(store: store)
    }

    MenuBarExtra {
      MenuBarView(store: store)
    } label: {
      MenuBarLabel(store: store)
    }

    Settings {
      SettingsView()
    }
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
