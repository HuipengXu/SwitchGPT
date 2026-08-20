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
          await store.refreshIfStale(
            maxAge: UsageRefreshPolicy.backgroundMaxAge,
            reportsActivity: false
          )
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
  @State private var hoveredAccountID: AccountID?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      menuActionButton(title: "Open Dashboard", systemImage: "rectangle.inset.filled") {
        openWindow(id: "dashboard")
      }

      Divider()
        .padding(.vertical, 7)

      Text("Accounts")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)

      VStack(alignment: .leading, spacing: 3) {
        ForEach(store.accounts) { account in
          accountButton(for: account)
        }
      }

      if let menuActivityText {
        Text(menuActivityText)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(menuActivityColor)
          .lineLimit(1)
          .padding(.horizontal, 8)
          .padding(.top, 8)
          .padding(.bottom, 2)
      }

      Divider()
        .padding(.vertical, 7)

      menuActionButton(title: "Refresh Usage", systemImage: "arrow.clockwise") {
        Task { await store.refresh() }
      }
      .disabled(store.activity.isBusy)

      menuActionButton(title: "Quit SwitchGPT", systemImage: "power") {
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(10)
    .frame(width: 390)
    .task {
      await store.refreshIfStale(
        maxAge: UsageRefreshPolicy.menuOpenMaxAge,
        reportsActivity: false
      )
    }
  }

  private func menuActionButton(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .frame(width: 16)
        Text(title)
          .font(.system(size: 13, weight: .medium))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
  }

  private func accountButton(for account: AccountRecord) -> some View {
    let isCurrent = store.currentAccountID.map { $0 == account.id } ?? false
    return Button {
      Task {
        await switchFromMenu(to: account)
      }
    } label: {
      Label {
        Text(menuTitle(for: account))
          .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
          .lineLimit(1)
          .truncationMode(.middle)
      } icon: {
        Image(systemName: account.symbolName)
          .frame(width: 16)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(
          isCurrent
            ? Color.accentColor.opacity(0.18)
            : hoveredAccountID == account.id
              ? Color.accentColor.opacity(0.12)
              : Color.clear
        )
    )
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .stroke(
          hoveredAccountID == account.id
            ? Color.accentColor.opacity(0.42)
            : Color.clear,
          lineWidth: 1
        )
    }
    .onHover { isHovered in
      if isHovered {
        hoveredAccountID = account.id
      } else if hoveredAccountID == account.id {
        hoveredAccountID = nil
      }
    }
    .animation(.easeOut(duration: 0.12), value: hoveredAccountID)
    .disabled(isCurrent || accountActionsDisabled)
  }

  private var menuActivityText: String? {
    if case .ready = store.activity {
      return nil
    }
    return store.activity.message
  }

  private func menuTitle(for account: AccountRecord) -> String {
    if store.currentAccountID.map({ $0 == account.id }) ?? false {
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

  private var accountActionsDisabled: Bool {
    switch store.activity {
    case .refreshing:
      return true
    case .simulating, .switching:
      return true
    case .ready, .success, .failure:
      return false
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
