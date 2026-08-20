import SwiftUI
import SwitchGPTAppCore

struct DashboardView: View {
  let store: SwitchGPTAppStore

  @State private var pendingSwitch: AccountRecord?
  @State private var pendingRealSwitch: RealSwitchPlan?
  @State private var pendingRemoval: AccountRecord?
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

  private var selectedAccountIsCurrent: Bool {
    guard let selectedAccount else { return false }
    return store.currentAccountID.map { $0 == selectedAccount.id } ?? false
  }

  private var selectedAccountAllowsCurrentAction: Bool {
    guard let selectedAccount else { return false }
    if case .codexHome = selectedAccount.source { return true }
    return false
  }

  private var onRemoveSelectedAccount: (() -> Void)? {
    guard let selectedAccount, canRemove(selectedAccount) else { return nil }
    return { pendingRemoval = selectedAccount }
  }

  private var isRemovalDialogPresented: Binding<Bool> {
    Binding(
      get: { pendingRemoval != nil },
      set: { isPresented in
        if !isPresented { pendingRemoval = nil }
      }
    )
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

      dashboardDetail
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
      if !store.accounts.isEmpty,
        store.lastRefreshedAt == nil || store.needsAccountMetadataRefresh
      {
        await store.refresh()
      } else if !store.accounts.isEmpty {
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

  private var dashboardDetail: some View {
    DashboardDetailView(
      store: store,
      account: selectedAccount,
      isCurrent: selectedAccountIsCurrent,
      allowsCurrentAction: selectedAccountAllowsCurrentAction,
      onPreviewSwitch: {
        if let selectedAccount {
          requestSwitch(to: selectedAccount)
        }
      },
      onRemove: onRemoveSelectedAccount
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .confirmationDialog("Remove account?", isPresented: isRemovalDialogPresented) {
      if let account = pendingRemoval {
        Button("Remove account", role: .destructive) {
          remove(account)
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Remove this account from SwitchGPT? Its saved local profile will be removed. "
          + "This does not delete the OpenAI account."
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
    guard store.currentAccountID.map({ $0 != account.id }) ?? true else { return }
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
    guard store.currentAccountID.map({ $0 != account.id }) ?? true else { return false }
    return store.accounts.count > 1
  }

  private func remove(_ account: AccountRecord) {
    store.removeAccount(account.id)
    selectedAccountID = store.currentAccountID ?? store.accounts.first?.id
  }
}
