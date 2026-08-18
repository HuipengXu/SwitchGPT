import SwiftUI
import SwitchGPTAppCore

struct SwitchGPTCommands: Commands {
  let store: SwitchGPTAppStore

  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("SwitchGPT") {
      Button("Open Dashboard") {
        openWindow(id: "dashboard")
      }
      .keyboardShortcut("0")

      Button("Refresh Usage") {
        Task { await store.refresh() }
      }
      .keyboardShortcut("r", modifiers: [.command, .option])
      .disabled(store.activity.isBusy)
    }

    CommandGroup(replacing: .appSettings) {}
    CommandGroup(replacing: .sidebar) {}
  }
}
