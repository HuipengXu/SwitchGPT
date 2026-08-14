import SwiftUI
import SwitchGPTAppCore

struct UsageWindowRow: View {
  let title: String
  let window: UsageWindow
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.subheadline)
        Spacer()
        Text(String(window.remainingPercent) + "% left")
          .font(.subheadline.weight(.medium).monospacedDigit())
          .foregroundStyle(accent)
      }

      ProgressView(value: Double(window.remainingPercent), total: 100)
        .tint(accent)
        .controlSize(.small)

      HStack {
        Text(String(window.usedPercent) + "% used")
        Spacer()
        Text("Resets " + window.resetAt.formatted(date: .abbreviated, time: .shortened))
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }
}
