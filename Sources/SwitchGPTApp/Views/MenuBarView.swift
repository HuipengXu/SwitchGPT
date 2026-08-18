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
        openWindow(id: "dashboard")
      }
      .task {
        while !Task.isCancelled {
          do {
            try await Task.sleep(for: UsageRefreshPolicy.backgroundInterval)
          } catch {
            return
          }
          await store.refreshIfStale(maxAge: UsageRefreshPolicy.backgroundMaxAge)
        }
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
    return account.accountLabel + ", " + quotaSummaryText(for: account)
  }
}

struct MenuBarView: View {
  let store: SwitchGPTAppStore

  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open Dashboard") {
      openWindow(id: "dashboard")
    }

    Divider()

    Text("Accounts")
      .font(.caption)
      .foregroundStyle(.secondary)

    ForEach(store.accounts) { account in
      Button {
        Task {
          await switchFromMenu(to: account)
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

    if case .ready = store.activity {
      EmptyView()
    } else {
      Text(store.activity.message)
        .font(.caption)
        .foregroundStyle(menuActivityColor)
    }

    Divider()

    Button("Refresh Usage") {
      Task { await store.refresh() }
    }
    .disabled(store.activity.isBusy)

    Divider()

    Button("Quit SwitchGPT") {
      NSApplication.shared.terminate(nil)
    }
    .task {
      await store.refreshIfStale(maxAge: UsageRefreshPolicy.menuOpenMaxAge)
    }
  }

  private func menuTitle(for account: AccountRecord) -> String {
    if account.id == store.currentAccountID {
      return
        account.compactAccountLabel() + " · Current · " + account.planName + " · "
        + quotaSummaryText(for: account)
    }
    return
      account.compactAccountLabel() + " · " + account.planName + " · "
      + quotaSummaryText(for: account)
  }

  private var menuActivityColor: Color {
    switch store.activity {
    case .failure:
      return ChatGPTStyle.dangerRed
    case .success:
      return ChatGPTStyle.successGreen
    case .refreshing, .simulating, .switching:
      return ChatGPTStyle.actionBlue
    case .ready:
      return .secondary
    }
  }

  @MainActor
  private func switchFromMenu(to account: AccountRecord) async {
    if case .mock = account.source {
      await store.simulateSwitch(to: account.id)
      return
    }
    do {
      let plan = try await RealSwitchWorkflow.prepare(targetID: account.id, store: store)
      guard
        MenuBarSwitchConfirmation.confirm(
          sourceName: plan.sourceAccount.accountLabel,
          targetName: plan.targetAccount.accountLabel,
          hasUnvalidatedChatGPTVersion: !plan.targetApplicationCompatibility.isValidated
        )
      else {
        store.resetActivity()
        return
      }
      await RealSwitchWorkflow.run(plan, store: store)
    } catch {
      store.failRealSwitch(message: RealSwitchWorkflow.userMessage(for: error))
    }
  }
}
