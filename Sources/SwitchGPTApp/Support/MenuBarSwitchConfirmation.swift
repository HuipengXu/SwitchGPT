import AppKit

@MainActor
enum MenuBarSwitchConfirmation {
  static func confirm(
    sourceName: String,
    targetName: String,
    hasUnvalidatedChatGPTVersion: Bool
  ) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Switch ChatGPT to \(targetName)?"
    let compatibilityNotice =
      hasUnvalidatedChatGPTVersion
      ? "\n\nThis ChatGPT version has not been validated with SwitchGPT yet. SwitchGPT will still try this switch; if the target cannot be verified, it restores the original account with one recovery launch."
      : ""
    alert.informativeText =
      "\(sourceName) → \(targetName)\n\nChatGPT will quit and reopen once. If verification fails, SwitchGPT will restore the original account using its independent one-shot recovery process.\(compatibilityNotice)"
    alert.addButton(withTitle: "Switch account")
    alert.addButton(withTitle: "Cancel")

    let noRunningTasks = NSButton(
      checkboxWithTitle: "No Work or Codex task is currently running",
      target: nil,
      action: nil
    )
    noRunningTasks.font = .systemFont(ofSize: 13)
    noRunningTasks.frame = NSRect(x: 0, y: 0, width: 390, height: 24)
    alert.accessoryView = noRunningTasks

    let switchButton = alert.buttons[0]
    switchButton.isEnabled = false
    let enabler = ConfirmationButtonEnabler(button: switchButton)
    noRunningTasks.target = enabler
    noRunningTasks.action = #selector(ConfirmationButtonEnabler.checkboxChanged(_:))

    NSApp.activate(ignoringOtherApps: true)
    let response = withExtendedLifetime(enabler) {
      alert.runModal()
    }
    return response == .alertFirstButtonReturn
  }
}

@MainActor
private final class ConfirmationButtonEnabler: NSObject {
  private let button: NSButton

  init(button: NSButton) {
    self.button = button
  }

  @objc func checkboxChanged(_ sender: NSButton) {
    button.isEnabled = sender.state == .on
  }
}
