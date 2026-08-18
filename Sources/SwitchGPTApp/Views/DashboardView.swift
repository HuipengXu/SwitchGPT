import SwiftUI
import SwitchGPTAppCore

struct DashboardView: View {
  let store: SwitchGPTAppStore

  @State private var pendingSwitch: AccountRecord?
  @State private var pendingRealSwitch: RealSwitchPlan?
  @State private var selectedAccountID: AccountID?
  @State private var accountSignInTask: Task<Void, Never>?
  @State private var windowTopInset: CGFloat = 0

  private var selectedAccount: AccountRecord? {
    if let selectedAccountID,
      let account = store.accounts.first(where: { $0.id == selectedAccountID })
    {
      return account
    }
    return store.currentAccount
  }

  var body: some View {
    HStack(spacing: 0) {
      SwitchGPTSidebar(
        store: store,
        selection: $selectedAccountID,
        topInset: windowTopInset,
        onAddOrCancel: addOrCancelAccountSignIn
      )
      .frame(width: ChatGPTStyle.sidebarWidth)

      Divider()

      DashboardDetailView(
        store: store,
        account: selectedAccount,
        isCurrent: selectedAccount?.id == store.currentAccountID,
        allowsCurrentAction: selectedAccount.map {
          if case .codexHome = $0.source { return true }
          return false
        } == true,
        onPreviewSwitch: {
          if let selectedAccount {
            requestSwitch(to: selectedAccount)
          }
        },
        onRemove: selectedAccount.map { account in
          canRemove(account) ? { remove(account) } : nil
        } ?? nil
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .tint(.primary)
    .frame(minWidth: 820, minHeight: 540)
    .ignoresSafeArea(.container, edges: .top)
    .background {
      WindowTopInsetReader { newInset in
        if abs(windowTopInset - newInset) > 0.5 {
          windowTopInset = newInset
        }
      }
    }
    .task {
      await store.bootstrapCurrentAccountIfNeeded()
      await store.preserveActiveAccountForSwitchingIfNeeded()
      await store.reconcileCurrentAccountWithDesktop()
      if selectedAccountID == nil {
        selectedAccountID = store.currentAccountID
      }
      if store.lastRefreshedAt == nil || store.needsAccountMetadataRefresh {
        await store.refresh()
      } else {
        await store.refreshIfStale(maxAge: UsageRefreshPolicy.dashboardVisibleMaxAge)
      }
    }
    .onChange(of: store.currentAccountID) { _, newValue in
      selectedAccountID = newValue
    }
    .onDisappear {
      accountSignInTask?.cancel()
    }
    .sheet(item: $pendingSwitch) { target in
      SwitchConfirmationSheet(
        current: store.currentAccount,
        target: target,
        isRealSwitch: false,
        showsUnvalidatedVersionWarning: false,
        onConfirm: {
          pendingSwitch = nil
          Task {
            await store.simulateSwitch(to: target.id)
          }
        }
      )
    }
    .sheet(item: $pendingRealSwitch) { plan in
      SwitchConfirmationSheet(
        current: plan.sourceAccount,
        target: plan.targetAccount,
        isRealSwitch: true,
        showsUnvalidatedVersionWarning: !plan.targetApplicationCompatibility.isValidated,
        onConfirm: {
          pendingRealSwitch = nil
          runRealSwitch(plan)
        }
      )
    }
  }

  private func addOrCancelAccountSignIn() {
    if store.accountOnboardingActivity.isInProgress {
      accountSignInTask?.cancel()
      return
    }
    guard accountSignInTask == nil, !store.activity.blocksAccountOnboarding else { return }
    accountSignInTask = Task {
      if let newID = await store.signInAccount() {
        selectedAccountID = newID
      }
      accountSignInTask = nil
    }
  }

  private func requestSwitch(to account: AccountRecord) {
    guard !store.activity.isBusy else { return }
    guard account.id != store.currentAccountID else { return }
    selectedAccountID = account.id
    if case .mock = account.source {
      pendingSwitch = account
    } else {
      Task {
        do {
          pendingRealSwitch = try await RealSwitchWorkflow.prepare(
            targetID: account.id,
            store: store
          )
        } catch {
          store.failRealSwitch(message: RealSwitchWorkflow.userMessage(for: error))
        }
      }
    }
  }

  private func runRealSwitch(_ plan: RealSwitchPlan) {
    Task {
      await RealSwitchWorkflow.run(plan, store: store)
    }
  }

  private func canRemove(_ account: AccountRecord) -> Bool {
    guard account.id != store.currentAccountID else { return false }
    return store.accounts.count > 1
  }

  private func remove(_ account: AccountRecord) {
    store.removeAccount(account.id)
    selectedAccountID = store.currentAccountID
  }
}
