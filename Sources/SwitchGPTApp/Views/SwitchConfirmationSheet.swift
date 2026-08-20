import SwiftUI
import SwitchGPTAppCore

struct SwitchConfirmationSheet: View {
  let current: AccountRecord?
  let target: AccountRecord
  let isRealSwitch: Bool
  let showsUnvalidatedVersionWarning: Bool
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var acknowledged = false
  @State private var noRunningTasks = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(isRealSwitch ? ChatGPTStyle.warningOrange : ChatGPTStyle.actionBlue)
          .frame(width: 36, height: 36)
          .background(
            ChatGPTStyle.semanticFill(
              isRealSwitch ? ChatGPTStyle.warningOrange : ChatGPTStyle.actionBlue
            ),
            in: Circle()
          )

        VStack(alignment: .leading, spacing: 3) {
          Text(isRealSwitch ? "Switch ChatGPT account?" : "Preview this account?")
            .font(.system(size: 18, weight: .semibold))
          Text(isRealSwitch ? "ChatGPT will restart once" : "ChatGPT will not be changed")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 12) {
        accountLabel(current?.accountLabel ?? "Current account")
        Image(systemName: "arrow.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
        accountLabel(target.accountLabel)
      }
      .padding(14)
      .frame(maxWidth: .infinity)
      .chatGPTPanel()

      Text(explanation)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if isRealSwitch && showsUnvalidatedVersionWarning {
        unvalidatedVersionWarning
      }

      VStack(alignment: .leading, spacing: 12) {
        Toggle(acknowledgementLabel, isOn: $acknowledged)
          .toggleStyle(.checkbox)

        if isRealSwitch {
          Toggle("No Work or Codex task is currently running", isOn: $noRunningTasks)
            .toggleStyle(.checkbox)
        }
      }
      .font(.system(size: 13))

      HStack(spacing: 10) {
        Spacer()
        Button("Cancel") {
          dismiss()
        }
        .buttonStyle(ChatGPTSecondaryButtonStyle())
        .keyboardShortcut(.cancelAction)

        Button(isRealSwitch ? "Switch account" : "Preview account") {
          onConfirm()
          dismiss()
        }
        .buttonStyle(ChatGPTPrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
        .disabled(!acknowledged || (isRealSwitch && !noRunningTasks))
      }
    }
    .padding(24)
    .frame(width: 470)
    .background(ChatGPTStyle.surface(for: colorScheme))
    .tint(ChatGPTStyle.actionBlue)
  }

  private func accountLabel(_ name: String) -> some View {
    HStack(spacing: 7) {
      Image(systemName: "person.crop.circle")
        .font(.system(size: 13))
      Text(name)
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
  }

  private var explanation: String {
    if isRealSwitch {
      return
        "SwitchGPT verifies the target account after ChatGPT restarts. If verification fails, the original account is restored by the independent one-shot recovery process."
    }
    return
      "This changes only local preview state so you can evaluate the flow. It does not quit ChatGPT, replace credentials, or install a background service."
  }

  private var acknowledgementLabel: String {
    isRealSwitch
      ? "I understand that ChatGPT will quit and reopen"
      : "I understand this is preview data only"
  }

  private var unvalidatedVersionWarning: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(ChatGPTStyle.warningOrange)

      VStack(alignment: .leading, spacing: 3) {
        Text("This ChatGPT version has not been validated with SwitchGPT yet.")
          .font(.system(size: 13, weight: .semibold))
        Text(
          "SwitchGPT will still try this switch. If the target cannot be verified, it restores the original account with one recovery launch."
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .background(
      ChatGPTStyle.semanticFill(ChatGPTStyle.warningOrange),
      in: RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
        .stroke(ChatGPTStyle.semanticBorder(ChatGPTStyle.warningOrange), lineWidth: 1)
    }
  }
}
