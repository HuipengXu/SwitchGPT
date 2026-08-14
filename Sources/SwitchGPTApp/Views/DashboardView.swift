import SwiftUI
import SwitchGPTAppCore

struct DashboardView: View {
  let store: SwitchGPTAppStore

  @State private var pendingSwitch: AccountRecord?
  @State private var showingAddAccount = false
  @State private var selectedAccountID: AccountID?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  private var selectedAccount: AccountRecord? {
    if let selectedAccountID,
      let account = store.accounts.first(where: { $0.id == selectedAccountID })
    {
      return account
    }
    return store.currentAccount
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      SwitchGPTSidebar(
        store: store,
        selection: $selectedAccountID,
        onAdd: { showingAddAccount = true }
      )
      .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
    } detail: {
      DashboardDetailView(
        store: store,
        account: selectedAccount,
        isCurrent: selectedAccount?.id == store.currentAccountID,
        onPreviewSwitch: {
          if let selectedAccount {
            requestSwitch(to: selectedAccount)
          }
        },
        onRemove: selectedAccount.map { account in
          canRemove(account) ? { remove(account) } : nil
        } ?? nil
      )
    }
    .navigationSplitViewStyle(.balanced)
    .tint(.primary)
    .frame(minWidth: 900, minHeight: 620)
    .task {
      if selectedAccountID == nil {
        selectedAccountID = store.currentAccountID
      }
      if store.lastRefreshedAt == nil {
        await store.refresh()
      }
    }
    .onChange(of: store.currentAccountID) { _, newValue in
      selectedAccountID = newValue
    }
    .sheet(item: $pendingSwitch) { target in
      SwitchConfirmationSheet(
        current: store.currentAccount,
        target: target,
        onConfirm: {
          pendingSwitch = nil
          Task {
            await store.simulateSwitch(to: target.id)
          }
        }
      )
    }
    .sheet(isPresented: $showingAddAccount) {
      AddMockAccountSheet { displayName, detail in
        if let newID = store.addMockAccount(displayName: displayName, detail: detail) {
          selectedAccountID = newID
        }
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          showingAddAccount = true
        } label: {
          Label("Add account", systemImage: "person.badge.plus")
        }

        Button {
          Task { await store.refresh() }
        } label: {
          Label("Refresh usage", systemImage: "arrow.clockwise")
        }
        .help("Refresh mock usage data")
        .disabled(store.activity.isBusy)
      }
    }
  }

  private func requestSwitch(to account: AccountRecord) {
    guard account.id != store.currentAccountID, !store.activity.isBusy else { return }
    selectedAccountID = account.id
    pendingSwitch = account
  }

  private func canRemove(_ account: AccountRecord) -> Bool {
    guard account.id != store.currentAccountID else { return false }
    if case .mock = account.source {
      return true
    }
    return false
  }

  private func remove(_ account: AccountRecord) {
    store.removeMockAccount(account.id)
    selectedAccountID = store.currentAccountID
  }
}
