import Foundation
import SwiftUI
import SwitchGPTAppCore

struct CreditsBalanceRow: View {
  let credits: CreditBalance

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Credits balance")
          .font(.system(size: 14, weight: .medium))
        Text("Current balance")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 16)

      Text(balanceText)
        .font(.system(size: 15, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
    }
    .accessibilityElement(children: .combine)
  }

  private var balanceText: String {
    if credits.unlimited {
      return "Unlimited"
    }
    if let balance = credits.usdBalance {
      let formatter = NumberFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = 2
      formatter.maximumFractionDigits = 2
      formatter.roundingMode = .halfUp
      let amount =
        formatter.string(from: NSDecimalNumber(decimal: balance))
        ?? NSDecimalNumber(decimal: balance).stringValue
      return "US$" + amount
    }
    return credits.hasCredits ? "Available" : "Unavailable"
  }
}
