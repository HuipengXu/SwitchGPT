import SwiftUI
import SwitchGPTAppCore

struct AccountCardView: View {
  let account: AccountRecord
  let isCurrent: Bool
  let allowsCurrentAction: Bool
  let isBusy: Bool
  let onPreviewSwitch: () -> Void
  let onRemove: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Work / Codex")
          .font(.system(size: 14, weight: .semibold))
        Spacer()
        Text(account.planName)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .frame(height: 44)

      Divider()
        .padding(.horizontal, 16)

      VStack(alignment: .leading, spacing: 18) {
        UsageWindowRow(
          title: "Weekly limit",
          window: account.usage.weekly
        )

        if let fiveHour = account.usage.fiveHour {
          Divider()

          UsageWindowRow(
            title: "5-hour limit",
            window: fiveHour
          )
        }

        if let credits = account.usage.credits, credits.isDisplayable {
          Divider()

          CreditsBalanceRow(credits: credits)
        }
      }
      .padding(16)

      Divider()
        .padding(.horizontal, 16)

      actionRow
        .padding(12)
    }
    .chatGPTPanel()
    .contextMenu {
      if let onRemove {
        Button("Remove account", role: .destructive, action: onRemove)
      }
    }
  }

  @ViewBuilder
  private var actionRow: some View {
    if isCurrent {
      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 13))
          .foregroundStyle(ChatGPTStyle.successGreen)
        Text(isMock ? "Current preview account" : "Current in ChatGPT")
          .font(.system(size: 13, weight: .medium))
        Spacer()
      }
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
      .frame(height: 36)
    } else {
      VStack(spacing: 8) {
        switchButton
        removeButton
      }
    }
  }

  @ViewBuilder
  private var switchButton: some View {
    if switchingAvailable {
      Button(action: onPreviewSwitch) {
        HStack {
          Text(actionLabel)
          Spacer()
          Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(ChatGPTPrimaryButtonStyle())
      .disabled(isBusy)
      .accessibilityHint(accessibilityHint)
    } else {
      Button(action: onPreviewSwitch) {
        HStack {
          Text(actionLabel)
          Spacer()
          Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(ChatGPTSecondaryButtonStyle())
      .disabled(isBusy)
      .accessibilityHint(accessibilityHint)
    }
  }

  @ViewBuilder
  private var removeButton: some View {
    if let onRemove {
      Button(role: .destructive, action: onRemove) {
        HStack {
          Image(systemName: "trash")
          Text("Remove account")
          Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(ChatGPTDestructiveButtonStyle())
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .disabled(isBusy)
      .accessibilityHint("Removes this saved account from SwitchGPT")
    }
  }

  private var isMock: Bool {
    if case .mock = account.source { return true }
    return false
  }

  private var switchingAvailable: Bool {
    allowsCurrentAction && !isMock
  }

  private var actionLabel: String {
    if isMock { return "Preview this account" }
    return switchingAvailable ? "Switch ChatGPT to this account" : "Show in menu bar"
  }

  private var accessibilityHint: String {
    if isMock { return "Opens a safe simulation confirmation" }
    return switchingAvailable
      ? "Opens the experimental switch confirmation"
      : "Selects this read-only quota for the menu bar"
  }
}
