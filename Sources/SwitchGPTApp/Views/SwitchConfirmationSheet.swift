import SwiftUI
import SwitchGPTAppCore

struct SwitchConfirmationSheet: View {
  let current: AccountRecord?
  let target: AccountRecord
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var acknowledged = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Preview account switch", systemImage: "arrow.triangle.2.circlepath")
        .font(.title3.weight(.semibold))

      Text("Preview " + (current?.displayName ?? "current account") + " → " + target.displayName)
        .font(.headline)

      Text("This is an offline UI simulation. It changes local mock state so you can evaluate the flow, but it will not quit ChatGPT, replace credentials, or register a background service.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Toggle("I understand this is simulation only", isOn: $acknowledged)
        .toggleStyle(.checkbox)

      HStack {
        Spacer()
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("Run simulation") {
          onConfirm()
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!acknowledged)
      }
    }
    .padding(26)
    .frame(width: 470)
  }
}
