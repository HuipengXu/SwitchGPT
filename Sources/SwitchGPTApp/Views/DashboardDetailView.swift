import SwiftUI
import SwitchGPTAppCore

struct DashboardDetailView: View {
  let store: SwitchGPTAppStore
  let account: AccountRecord?
  let isCurrent: Bool
  let allowsCurrentAction: Bool
  let onPreviewSwitch: () -> Void
  let onRemove: (() -> Void)?

  @Environment(\.colorScheme) private var colorScheme
  @State private var refreshFeedback: RefreshFeedback = .idle
  @State private var refreshTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 0) {
      topBar

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          if let account {
            accountHeader(account)

            if !isReady {
              activityBanner
            }

            AccountCardView(
              account: account,
              isCurrent: isCurrent,
              allowsCurrentAction: allowsCurrentAction,
              isBusy: store.activity.isBusy,
              onPreviewSwitch: onPreviewSwitch,
              onRemove: onRemove
            )
          } else {
            ContentUnavailableView(
              "No account selected",
              systemImage: "person.crop.circle.badge.questionmark",
              description: Text("Add an account from the sidebar to begin.")
            )
          }
        }
        .chatGPTContentColumn()
        .padding(.vertical, 30)
      }
    }
    .background(ChatGPTStyle.surface(for: colorScheme))
    .onDisappear {
      refreshTask?.cancel()
    }
  }

  private var topBar: some View {
    HStack(spacing: 0) {
      toolbarTitle

      Spacer(minLength: 8)

      if let refreshStatusText {
        Label(refreshStatusText, systemImage: displayedRefreshFeedback.symbolName)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(displayedRefreshFeedback.color)
          .padding(.trailing, 8)
          .accessibilityLabel(refreshStatusText)
      }

      Button {
        refreshUsage()
      } label: {
        if isRefreshing {
          ProgressView()
            .controlSize(.small)
            .tint(ChatGPTStyle.actionBlue)
        } else {
          Image(systemName: "arrow.clockwise")
            .foregroundStyle(ChatGPTStyle.actionBlue)
        }
      }
      .buttonStyle(ChatGPTIconButtonStyle())
      .help(isRefreshing ? "Refreshing usage" : "Refresh usage")
      .accessibilityLabel(isRefreshing ? "Refreshing usage" : "Refresh usage")
      .disabled(isRefreshing || store.activity.isBusy)
    }
    .padding(.trailing, ChatGPTStyle.toolbarHorizontalInset)
    .frame(height: ChatGPTStyle.toolbarHeight)
  }

  private var toolbarTitle: some View {
    HStack(spacing: 10) {
      Text("Usage")
        .font(.system(size: 14, weight: .semibold))

      if let account {
        Text("·")
          .foregroundStyle(.tertiary)
        Text(account.accountLabel)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .frame(maxWidth: 350, alignment: .leading)
    .padding(.leading, ChatGPTStyle.toolbarHorizontalInset)
  }

  private var isRefreshing: Bool {
    if refreshFeedback == .refreshing { return true }
    if case .refreshing = store.activity { return true }
    return false
  }

  private var displayedRefreshFeedback: RefreshFeedback {
    if refreshFeedback == .idle, case .refreshing = store.activity {
      return .refreshing
    }
    return refreshFeedback
  }

  private var refreshStatusText: String? {
    switch refreshFeedback {
    case .idle:
      if case .refreshing = store.activity { return "Refreshing" }
      return nil
    case .refreshing:
      return "Refreshing"
    case .updated:
      return "Updated"
    case .failed:
      return "Refresh failed"
    }
  }

  private func refreshUsage() {
    guard !isRefreshing, !store.activity.isBusy else { return }
    refreshTask?.cancel()
    refreshFeedback = .refreshing

    refreshTask = Task { @MainActor in
      // Yield a frame before the reader starts. This gives the user visible feedback
      // even when a cached or local response completes immediately.
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      await store.refresh()
      guard !Task.isCancelled else { return }

      switch store.activity {
      case .success:
        refreshFeedback = .updated
      case .failure:
        refreshFeedback = .failed
      default:
        refreshFeedback = .idle
      }
    }
  }

  private enum RefreshFeedback {
    case idle
    case refreshing
    case updated
    case failed

    var symbolName: String {
      switch self {
      case .idle:
        return "arrow.clockwise"
      case .refreshing:
        return "arrow.triangle.2.circlepath"
      case .updated:
        return "checkmark.circle.fill"
      case .failed:
        return "exclamationmark.circle.fill"
      }
    }

    var color: Color {
      switch self {
      case .idle:
        return ChatGPTStyle.actionBlue
      case .refreshing:
        return ChatGPTStyle.actionBlue
      case .updated:
        return ChatGPTStyle.successGreen
      case .failed:
        return ChatGPTStyle.dangerRed
      }
    }
  }

  private func accountHeader(_ account: AccountRecord) -> some View {
    HStack(spacing: 12) {
      Image(systemName: account.symbolName)
        .font(.system(size: 15, weight: .medium))
        .frame(width: 38, height: 38)
        .background(ChatGPTStyle.subtleFill, in: Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(account.accountLabel)
          .font(.system(size: 18, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.middle)
          .help(account.accountLabel)
        Text(account.planName)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      if isCurrent {
        Label("Current", systemImage: "checkmark")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(ChatGPTStyle.successGreen)
          .padding(.horizontal, 9)
          .frame(height: 26)
          .background(
            ChatGPTStyle.semanticFill(ChatGPTStyle.successGreen),
            in: Capsule()
          )
      }
    }
  }

  private var activityBanner: some View {
    HStack(spacing: 10) {
      Image(systemName: activitySymbol)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(activityColor)
      Text(store.activity.message)
        .font(.system(size: 13))
      Spacer()
      if !store.activity.isBusy {
        Button("Dismiss") {
          store.resetActivity()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(activityColor)
      }
    }
    .padding(.horizontal, 14)
    .frame(minHeight: 42)
    .background(
      ChatGPTStyle.semanticFill(activityColor),
      in: RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
        .stroke(ChatGPTStyle.semanticBorder(activityColor), lineWidth: 1)
    }
  }

  private var isReady: Bool {
    if case .ready = store.activity { return true }
    return false
  }

  private var activitySymbol: String {
    switch store.activity {
    case .ready:
      return "checkmark"
    case .refreshing:
      return "arrow.clockwise"
    case .simulating, .switching:
      return "arrow.triangle.2.circlepath"
    case .success:
      return "checkmark.circle.fill"
    case .failure:
      return "exclamationmark.triangle.fill"
    }
  }

  private var activityColor: Color {
    switch store.activity {
    case .ready, .success:
      return ChatGPTStyle.successGreen
    case .refreshing, .simulating, .switching:
      return ChatGPTStyle.actionBlue
    case .failure:
      return ChatGPTStyle.dangerRed
    }
  }
}
