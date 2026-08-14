import SwiftUI

struct AddMockAccountSheet: View {
  @Environment(\.dismiss) private var dismiss

  @State private var displayName = ""
  @State private var detail = ""

  let onAdd: (String, String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Add account")
          .font(.title2.weight(.semibold))
        Text("Add another local mock account to exercise the multi-account layout. Real login onboarding is not connected yet.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Form {
        TextField("Display name", text: $displayName)
        TextField("Workspace detail", text: $detail)
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("Add mock account") {
          onAdd(displayName, detail)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 440, height: 285)
  }
}
