import SwiftUI
import SwitchGPTAppCore

struct QuotaSummaryBar: View {
  let account: AccountRecord?
  let accountCount: Int
  let isCurrent: Bool

  var body: some View {
    HStack(spacing: 0) {
      if let account {
        QuotaSummaryMetric(
          title: "Weekly quota",
          window: account.usage.weekly,
          tint: account.accent.color
        )

        if let fiveHour = account.usage.fiveHour {
          quotaDivider

          QuotaSummaryMetric(
            title: "5-hour quota",
            window: fiveHour,
            tint: account.accent.color.opacity(0.78)
          )
        }

        Spacer(minLength: 16)

        VStack(alignment: .trailing, spacing: 3) {
          Text(account.displayName)
            .font(.subheadline.weight(.semibold))
          Text((isCurrent ? "Current account · " : "Preview account · ") + String(accountCount) + " total")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        Text("No account selected")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }

  private var quotaDivider: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.16))
      .frame(width: 1, height: 34)
      .padding(.horizontal, 16)
      .accessibilityHidden(true)
  }
}

private struct QuotaSummaryMetric: View {
  let title: String
  let window: UsageWindow
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(String(window.remainingPercent) + "%")
          .font(.title3.weight(.bold).monospacedDigit())
          .foregroundStyle(tint)
        Text("left")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
