import SwiftUI
import SwitchGPTAppCore

struct MenuBarLabel: View {
  let store: SwitchGPTAppStore

  @Environment(\.openWindow) private var openWindow
  @State private var didRequestDashboard = false

  var body: some View {
    Text(menuBarQuota)
      .monospacedDigit()
      .accessibilityLabel(accessibilityQuotaLabel)
    .task {
      guard !didRequestDashboard else { return }
      didRequestDashboard = true
      openWindow(id: "main")
    }
  }

  private var menuBarQuota: String {
    guard let account = store.currentAccount else {
      return "—"
    }
    return quotaSummaryText(for: account)
  }

  private var accessibilityQuotaLabel: String {
    guard let account = store.currentAccount else {
      return "No account selected"
    }
    return account.displayName + ", " + quotaSummaryText(for: account)
  }
}

struct MenuBarView: View {
  let store: SwitchGPTAppStore

  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open Dashboard") {
      openWindow(id: "main")
    }

    Divider()

    Text("Accounts")
      .font(.caption)
      .foregroundStyle(.secondary)

    ForEach(store.accounts) { account in
      Button {
        Task {
          await store.simulateSwitch(to: account.id)
          openWindow(id: "main")
        }
      } label: {
        Label {
          Text(menuTitle(for: account))
        } icon: {
          Image(systemName: account.symbolName)
        }
      }
      .disabled(account.id == store.currentAccountID || store.activity.isBusy)
    }

    Divider()

    Button("Refresh Usage") {
      Task { await store.refresh() }
    }
    .disabled(store.activity.isBusy)

    SettingsLink {
      Text("Settings…")
    }

    Divider()

    Button("Quit SwitchGPT") {
      NSApplication.shared.terminate(nil)
    }
  }

  private func menuTitle(for account: AccountRecord) -> String {
    if account.id == store.currentAccountID {
      return account.displayName + " · Current preview · " + quotaSummaryText(for: account)
    }
    return "Preview " + account.displayName + " · " + quotaSummaryText(for: account)
  }
}
