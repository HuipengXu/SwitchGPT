import Foundation
import SwitchGPTAppCore

enum RealSwitchWorkflowError: Error, LocalizedError {
  case targetUnavailable
  case quotaRefreshFailed

  var errorDescription: String? {
    switch self {
    case .targetUnavailable:
      return "The selected account is no longer configured."
    case .quotaRefreshFailed:
      return "The selected account could not be refreshed before switching."
    }
  }
}

@MainActor
enum RealSwitchWorkflow {
  static func prepare(targetID: AccountID, store: SwitchGPTAppStore) async throws
    -> RealSwitchPlan
  {
    guard await store.refreshAccount(targetID) else {
      throw RealSwitchWorkflowError.quotaRefreshFailed
    }
    guard let target = store.accounts.first(where: { $0.id == targetID }) else {
      throw RealSwitchWorkflowError.targetUnavailable
    }
    let accounts = store.accounts
    return try await Task.detached(priority: .userInitiated) {
      try ExperimentalRealSwitchCoordinator.preflight(
        target: target,
        accounts: accounts
      )
    }.value
  }

  static func run(_ plan: RealSwitchPlan, store: SwitchGPTAppStore) async {
    guard store.beginRealSwitch(to: plan.targetAccount.id) else { return }
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try ExperimentalRealSwitchCoordinator.perform(plan)
      }.value
      switch result.outcome {
      case .committed:
        store.completeRealSwitch(
          to: plan.targetAccount.id,
          receiptRecorded: result.receiptRecorded
        )
        await store.refresh()
        store.completeRealSwitch(
          to: plan.targetAccount.id,
          receiptRecorded: result.receiptRecorded
        )
      case .rolledBack:
        store.failRealSwitch(
          message:
            "Switch failed safely; the original account was restored and ChatGPT was relaunched once."
            + receiptSuffix(recorded: result.receiptRecorded)
        )
      case .manualRecoveryRequired:
        store.failRealSwitch(
          message:
            "Automatic recovery stopped after its single launch budget. Manual recovery is required."
            + receiptSuffix(recorded: result.receiptRecorded)
        )
      }
    } catch {
      store.failRealSwitch(message: userMessage(for: error))
    }
  }

  static func userMessage(for error: Error) -> String {
    if let error = error as? ExperimentalRealSwitchError,
      let message = error.errorDescription
    {
      return message
    }
    if let error = error as? RealSwitchWorkflowError,
      let message = error.errorDescription
    {
      return message
    }
    return "The experimental switch was blocked by a safety check; ChatGPT was not changed."
  }

  private static func receiptSuffix(recorded: Bool) -> String {
    recorded
      ? " A private metadata-only verification receipt was saved."
      : " The local verification receipt could not be saved."
  }
}
