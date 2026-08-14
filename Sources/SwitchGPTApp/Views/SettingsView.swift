import SwiftUI

struct SettingsView: View {
  var body: some View {
    Form {
      Section("Mode") {
        LabeledContent("Usage source", value: "Local mock data")
        LabeledContent("Account switching", value: "Simulation only")
      }

      Section("Safety boundary") {
        Label("Real switching is disabled in this build.", systemImage: "checkmark.shield.fill")
          .foregroundStyle(.primary)
        Text("The future experimental switcher must remain an explicit opt-in flow. It is not wired to ChatGPT, authentication files, launchd, or SMAppService yet.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    .tint(.primary)
    .frame(width: 470, height: 280)
    .scenePadding()
  }
}
