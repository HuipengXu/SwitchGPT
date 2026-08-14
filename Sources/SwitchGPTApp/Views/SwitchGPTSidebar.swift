import SwiftUI
import SwitchGPTAppCore

struct SwitchGPTSidebar: View {
  let store: SwitchGPTAppStore
  @Binding var selection: AccountID?
  let onAdd: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "sparkles")
          .font(.headline)
          .foregroundStyle(.primary)
          .frame(width: 26, height: 26)
          .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        Text("SwitchGPT")
          .font(.headline.weight(.semibold))

        Spacer(minLength: 8)

        Button(action: onAdd) {
          Image(systemName: "square.and.pencil")
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.plain)
        .help("Add account")
      }
      .padding(.horizontal, 16)
      .padding(.top, 16)
      .padding(.bottom, 14)

      Button(action: onAdd) {
        HStack(spacing: 9) {
          Image(systemName: "person.badge.plus")
          Text("Add account")
            .font(.subheadline.weight(.medium))
          Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 12)
      .padding(.bottom, 18)

      HStack {
        Text("Accounts")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text(String(store.accounts.count))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 6)

      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(store.accounts) { account in
            Button {
              selection = account.id
            } label: {
              AccountSidebarRow(
                account: account,
                isCurrent: account.id == store.currentAccountID
              )
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                selection == account.id ? Color.primary.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
      .scrollIndicators(.automatic)
      .padding(.horizontal, 2)

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.plain)

        HStack(spacing: 8) {
          Image(systemName: "checkmark.shield.fill")
            .foregroundStyle(.primary)
          Text("Safe preview mode")
            .font(.caption)
          Spacer()
        }
        .foregroundStyle(.secondary)
      }
      .padding(16)
    }
    .background(.regularMaterial)
  }
}

private struct AccountSidebarRow: View {
  let account: AccountRecord
  let isCurrent: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: account.symbolName)
        .font(.subheadline)
        .foregroundStyle(account.accent.color)
        .frame(width: 24, height: 24)
        .background(account.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        Text(account.displayName)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
        Text(quotaSummaryText(for: account))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      if isCurrent {
        Circle()
          .fill(.primary)
          .frame(width: 7, height: 7)
          .accessibilityLabel("Current")
      }
    }
    .padding(.vertical, 3)
    .contentShape(Rectangle())
  }
}
