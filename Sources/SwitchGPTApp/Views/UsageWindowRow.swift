import SwiftUI
import SwitchGPTAppCore

struct UsageWindowRow: View {
  let title: String
  let window: UsageWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
        Spacer()
        Text(String(window.remainingPercent) + "% left")
          .font(.system(size: 20, weight: .semibold).monospacedDigit())
          .foregroundStyle(quotaColor)
      }

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.primary.opacity(0.08))
          Capsule()
            .fill(quotaColor.opacity(isQuotaLow ? 0.9 : 0.78))
            .frame(
              width: proxy.size.width * CGFloat(window.remainingPercent) / 100
            )
        }
      }
      .frame(height: 5)
      .accessibilityElement()
      .accessibilityLabel(title)
      .accessibilityValue(String(window.remainingPercent) + "% left")

      HStack {
        Text(String(window.usedPercent) + "% used")
        Spacer()
        Text("Resets " + window.resetAt.formatted(date: .abbreviated, time: .shortened))
      }
      .font(.system(size: 12).monospacedDigit())
      .foregroundStyle(.secondary)
    }
  }

  private var quotaColor: Color {
    if window.remainingPercent <= 5 {
      return ChatGPTStyle.dangerRed
    }
    if window.remainingPercent <= 20 {
      return ChatGPTStyle.warningOrange
    }
    return .primary
  }

  private var isQuotaLow: Bool {
    window.remainingPercent <= 20
  }
}
