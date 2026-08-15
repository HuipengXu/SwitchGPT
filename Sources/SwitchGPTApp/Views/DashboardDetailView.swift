import SwiftUI
import SwitchGPTAppCore

struct DashboardDetailView: View {
  let store: SwitchGPTAppStore
  let account: AccountRecord?
  let isCurrent: Bool
  let onPreviewSwitch: () -> Void
  let onRemove: (() -> Void)?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        topBar
        Divider()

        VStack(alignment: .leading, spacing: 24) {
          if let account {
            accountIntro(account)

            QuotaSummaryBar(
              account: account,
              accountCount: store.accounts.count,
              isCurrent: isCurrent
            )

            if !isReady {
              activityBanner
            }

            AccountCardView(
              account: account,
              isCurrent: isCurrent,
              isBusy: store.activity.isBusy,
              onPreviewSwitch: onPreviewSwitch,
              onRemove: onRemove
            )

            safetyNotice
          } else {
            ContentUnavailableView(
              "No account selected",
              systemImage: "person.crop.circle.badge.questionmark",
              description: Text("Add an account from the sidebar to begin.")
            )
          }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .center)
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var topBar: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Usage")
          .font(.headline.weight(.semibold))
        Text(account?.displayName ?? "Accounts")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isCurrent {
        Label("Current preview", systemImage: "checkmark.circle.fill")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      } else if account != nil {
        Text("Preview only")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 40)
    .padding(.vertical, 16)
  }

  private func accountIntro(_ account: AccountRecord) -> some View {
    HStack(spacing: 14) {
      Image(systemName: account.symbolName)
        .font(.title2)
        .foregroundStyle(account.accent.color)
        .frame(width: 46, height: 46)
        .background(account.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(account.displayName)
          .font(.title2.weight(.semibold))
        Text(account.detail + " · " + account.planName)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)
    }
  }

  private var activityBanner: some View {
    HStack(spacing: 10) {
      Image(systemName: activitySymbol)
        .foregroundStyle(activityTint)
      Text(store.activity.message)
        .font(.callout.weight(.medium))
      Spacer()
      if !store.activity.isBusy {
        Button("Dismiss") {
          store.resetActivity()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.primary)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(activityTint.opacity(0.24), lineWidth: 1)
    }
  }

  private var safetyNotice: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checkmark.shield.fill")
        .font(.title3)
        .foregroundStyle(.primary)

      VStack(alignment: .leading, spacing: 5) {
        Text("Safe preview mode")
          .font(.subheadline.weight(.semibold))
        Text("All accounts and quotas in this build are mock data. ChatGPT, credentials, launchd, and SMAppService are untouched.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var isReady: Bool {
    if case .ready = store.activity {
      return true
    }
    return false
  }

  private var activitySymbol: String {
    switch store.activity {
    case .ready:
      return "checkmark.circle"
    case .refreshing:
      return "arrow.clockwise"
    case .simulating:
      return "arrow.triangle.2.circlepath"
    case .success:
      return "checkmark.circle.fill"
    case .failure:
      return "exclamationmark.triangle.fill"
    }
  }

  private var activityTint: Color {
    .primary
  }
}
