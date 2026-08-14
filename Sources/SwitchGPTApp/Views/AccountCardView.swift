import SwiftUI
import SwitchGPTAppCore

struct AccountCardView: View {
  let account: AccountRecord
  let isCurrent: Bool
  let isBusy: Bool
  let onPreviewSwitch: () -> Void
  let onRemove: (() -> Void)?

  @State private var isHovered = false

  var body: some View {
    Button(action: onPreviewSwitch) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 12) {
          Image(systemName: account.symbolName)
            .font(.headline)
            .foregroundStyle(account.accent.color)
            .frame(width: 34, height: 34)
            .background(account.accent.color.opacity(0.14), in: Circle())

          VStack(alignment: .leading, spacing: 3) {
            Text(account.displayName)
              .font(.headline.weight(.semibold))
            Text(account.detail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer(minLength: 8)

          if isCurrent {
            Label("Current", systemImage: "checkmark.circle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          } else {
            Text("Preview")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
        }

        Divider()

        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Text("Work / Codex")
              .font(.subheadline.weight(.semibold))
            Spacer()
            Text(account.planName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          UsageWindowRow(
            title: "Weekly window",
            window: account.usage.weekly,
            accent: account.accent.color
          )

          if let fiveHour = account.usage.fiveHour {
            UsageWindowRow(
              title: "5-hour window",
              window: fiveHour,
              accent: account.accent.color.opacity(0.78)
            )
          }
        }

        HStack {
          Text(isCurrent ? "Active desktop identity" : "Click to preview this account")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          if !isCurrent {
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(account.accent.color)
          }
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        (isHovered && !isCurrent && !isBusy ? Color.primary.opacity(0.055) : Color.primary.opacity(0.035)),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(
            isCurrent ? account.accent.color.opacity(0.36) : Color.primary.opacity(isHovered ? 0.14 : 0.08),
            lineWidth: 1
          )
      }
      .animation(.easeOut(duration: 0.14), value: isHovered)
    }
    .buttonStyle(.plain)
    .disabled(isCurrent || isBusy)
    .onHover { isHovered = $0 }
    .contextMenu {
      if let onRemove {
        Button("Remove mock account", role: .destructive, action: onRemove)
      }
    }
    .accessibilityHint(isCurrent ? "This is the current account" : "Opens a safe simulation confirmation")
  }
}
