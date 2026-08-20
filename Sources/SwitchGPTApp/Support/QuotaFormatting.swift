import SwitchGPTAppCore

func quotaSummaryText(for account: AccountRecord) -> String {
  var values = ["W " + String(account.usage.weekly.remainingPercent) + "%"]
  if let fiveHour = account.usage.fiveHour {
    values.append("5h " + String(fiveHour.remainingPercent) + "%")
  }
  return values.joined(separator: " │ ")
}
