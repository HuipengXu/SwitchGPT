import SwiftUI
import SwitchGPTAppCore

struct SwitchGPTSidebar: View {
  let store: SwitchGPTAppStore
  @Binding var selection: AccountID?
  let topInset: CGFloat
  let onAddOrCancel: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 2) {
        SidebarActionRow(
          title: store.accountOnboardingActivity.isInProgress
            ? "Cancel sign-in" : "Add account",
          symbol: store.accountOnboardingActivity.isInProgress ? "xmark" : "plus",
          action: onAddOrCancel
        )

        if store.accountOnboardingActivity.isInProgress {
          AccountOnboardingStatusRow(
            message: "Complete sign-in in your browser",
            isFailure: false,
            onDismiss: nil
          )
        } else if let message = store.accountOnboardingActivity.failureMessage {
          AccountOnboardingStatusRow(
            message: message,
            isFailure: true,
            onDismiss: store.resetAccountOnboardingActivity
          )
        }

        HStack {
          Text("Accounts")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
          Spacer()
          Text(String(store.accounts.count))
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .padding(.bottom, 5)
      }
      .padding(.horizontal, 8)

      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(store.accounts) { account in
            Button {
              selection = account.id
            } label: {
              AccountSidebarRow(
                account: account,
                isCurrent: store.currentAccountID.map { $0 == account.id } ?? false,
                isSelected: selection == account.id
              )
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
      }
      .scrollIndicators(.automatic)

      VStack(spacing: 2) {
        HStack(spacing: 8) {
          Image(systemName: "lock.fill")
            .font(.system(size: 10, weight: .medium))
          Text("Accounts stay on this Mac")
            .font(.system(size: 11))
          Spacer()
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .frame(height: 28)
      }
      .padding(.horizontal, 8)
      .padding(.top, 8)
      .padding(.bottom, 10)
      .overlay(alignment: .top) {
        Divider()
      }
    }
    .padding(.top, topInset)
    .background(ChatGPTStyle.sidebarBackground(for: colorScheme))
  }
}

private struct AccountOnboardingStatusRow: View {
  let message: String
  let isFailure: Bool
  let onDismiss: (() -> Void)?

  var body: some View {
    HStack(spacing: 8) {
      if isFailure {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundStyle(ChatGPTStyle.dangerRed)
      } else {
        ProgressView()
          .controlSize(.mini)
          .tint(ChatGPTStyle.actionBlue)
      }

      Text(message)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(2)

      Spacer(minLength: 4)

      if let onDismiss {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Dismiss")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }
}

private struct SidebarActionRow: View {
  let title: String
  let symbol: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(ChatGPTStyle.actionBlue)
          .frame(width: 20)
        Text(title)
          .font(.system(size: 14))
        Spacer()
      }
      .padding(.horizontal, 10)
      .frame(height: 34)
      .background(
        isHovered ? ChatGPTStyle.hoverFill : Color.clear,
        in: RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.15), value: isHovered)
  }
}

private struct AccountSidebarRow: View {
  let account: AccountRecord
  let isCurrent: Bool
  let isSelected: Bool

  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: account.symbolName)
        .font(.system(size: 12, weight: .medium))
        .frame(width: 26, height: 26)
        .background(ChatGPTStyle.subtleFill, in: Circle())

      VStack(alignment: .leading, spacing: 1) {
        Text(account.accountLabel)
          .font(.system(size: 14, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)
          .help(account.accountLabel)
        Text(account.planName + " · " + quotaSummaryText(for: account))
          .font(.system(size: 12).monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      if isCurrent {
        Image(systemName: "checkmark")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(ChatGPTStyle.successGreen)
          .accessibilityLabel("Current account")
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 42)
    .background(
      isSelected ? ChatGPTStyle.hoverFill : (isHovered ? ChatGPTStyle.subtleFill : Color.clear),
      in: RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
    )
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.15), value: isHovered)
  }
}
