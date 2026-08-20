import AppKit
import Darwin
import Foundation
import OSLog
import SwitchGPTLifecycleContract
import SwitchGPTServiceManagementMutation
import SwitchGPTServiceManagementStatus

@main
@MainActor
enum LifecycleActivationHostCLI {
  private static let logger = Logger(
    subsystem: LifecycleBundleContract.bundleIdentifier,
    category: "LifecycleActivationHost"
  )

  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["validate-bundle"] {
      do {
        try LifecycleBundleContract.validate(bundleURL: enclosingBundleURL())
        writeJSON(HostReport(outcome: "valid"))
        exit(0)
      } catch {
        writeJSON(HostReport(outcome: "invalidBundle"))
        exit(1)
      }
    }
    if arguments == ["registration-preflight"] {
      do {
        try RecoveryAgentRegistrationPreflight(bundleURL: enclosingBundleURL())
          .validateForRegistration()
        writeJSON(HostReport(outcome: "ready"))
        exit(0)
      } catch {
        writeJSON(HostReport(outcome: "notReady"))
        exit(1)
      }
    }
    if arguments == ["validate-install-location"] {
      do {
        try LifecycleActivationInstallContract.validate(bundleURL: enclosingBundleURL())
        writeJSON(HostReport(outcome: "validInstallLocation"))
        exit(0)
      } catch {
        writeJSON(HostReport(outcome: "invalidInstallLocation"))
        exit(1)
      }
    }
    if arguments == ["service-status"] {
      runStatusApplication()
    }
    if arguments == ["phase-c-delivery-status"] {
      writeJSON(readPhaseCDeliveryStatus())
      exit(0)
    }
    guard
      arguments == [
        "phase-b-register-and-unregister",
        "--confirm-system-service-mutation",
      ]
        || arguments == ["phase-b-emergency-unregister"]
        || arguments == [
          "phase-c-register-for-reboot",
          "--confirm-system-service-mutation",
          "--confirm-reboot-required",
        ]
        || arguments == [
          "phase-c-unregister-after-reboot",
          "--confirm-system-service-mutation",
        ]
        || arguments == ["phase-c-emergency-unregister"]
    else {
      writeJSON(HostReport(outcome: "invalidInvocation"))
      exit(64)
    }
    runApplication(command: arguments[0])
  }

  private static func runApplication(command: String) -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    DispatchQueue.main.async {
      let report = run(command: command)
      logger.notice("outcome=\(report.outcome, privacy: .public)")
      writeJSON(report)
      application.terminate(nil)
    }
    application.run()
    exit(0)
  }

  private static func runStatusApplication() -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    DispatchQueue.main.async {
      writeJSON(
        HostReport(outcome: RecoveryAgentStatusReader.read().rawValue)
      )
      application.terminate(nil)
    }
    application.run()
    exit(0)
  }

  private static func run(command: String) -> HostReport {
    let bundleURL = enclosingBundleURL()
    do {
      try LifecycleActivationInstallContract.validate(bundleURL: bundleURL)
      try RecoveryAgentRegistrationPreflight(bundleURL: bundleURL)
        .validateForRegistration()
    } catch {
      return HostReport(outcome: "preflightFailed")
    }

    switch command {
    case "phase-b-register-and-unregister", "phase-b-emergency-unregister":
      return runPhaseB(command: command, bundleURL: bundleURL)
    case "phase-c-register-for-reboot":
      return runPhaseCRegistration(bundleURL: bundleURL)
    case "phase-c-unregister-after-reboot":
      return runPhaseCUnregistration(bundleURL: bundleURL, emergency: false)
    case "phase-c-emergency-unregister":
      return runPhaseCUnregistration(bundleURL: bundleURL, emergency: true)
    default:
      return HostReport(outcome: "invalidInvocation")
    }
  }

  private static func runPhaseB(command: String, bundleURL: URL) -> HostReport {
    let recorder: PersistentActivationAttemptRecorder
    do {
      recorder = try PersistentActivationAttemptRecorder(session: .immediateLifecycle)
    } catch {
      return HostReport(outcome: "ledgerUnavailable")
    }

    let sessionLock: LifecycleActivationSessionLock
    do {
      sessionLock = try LifecycleActivationSessionLock(sessionURL: recorder.sessionURL)
    } catch {
      return HostReport(outcome: "sessionBusyOrUnsafe")
    }
    defer { sessionLock.release() }

    let service = RecoveryAgentServiceController()
    let controller = LifecycleActivationController(
      service: service,
      attemptRecorder: recorder,
      preflight: RecoveryAgentRegistrationPreflight(bundleURL: bundleURL)
    )

    if command == "phase-b-emergency-unregister" {
      do {
        guard try recorder.hasReservation(.registration) else {
          return HostReport(outcome: "ownershipNotEstablished")
        }
      } catch {
        return HostReport(outcome: "ledgerUnavailable")
      }
      let unregistration = controller.unregisterAfterRegistrationAttempt()
      return HostReport(
        outcome: "emergencyUnregistrationCompleted",
        unregistration: unregistration
      )
    }

    let report = ImmediateLifecycleValidationController(
      activationController: controller
    ).run()
    return HostReport(
      outcome: "immediateLifecycleCompleted",
      registration: report.registration,
      unregistration: report.unregistration
    )
  }

  private static func runPhaseCRegistration(bundleURL: URL) -> HostReport {
    let recorder: PersistentActivationAttemptRecorder
    let evidenceStore: RebootDeliveryEvidenceStore
    do {
      recorder = try PersistentActivationAttemptRecorder(session: .rebootLifecycle)
      evidenceStore = try RebootDeliveryEvidenceStore(sessionURL: recorder.sessionURL)
    } catch {
      return HostReport(outcome: "ledgerUnavailable")
    }

    let sessionLock: LifecycleActivationSessionLock
    do {
      sessionLock = try LifecycleActivationSessionLock(sessionURL: recorder.sessionURL)
    } catch {
      return HostReport(outcome: "sessionBusyOrUnsafe")
    }
    defer { sessionLock.release() }

    let service = RecoveryAgentServiceController()
    let report: RebootLifecycleValidationReport
    do {
      report = RebootLifecycleValidationController(
        activationController: LifecycleActivationController(
          service: service,
          attemptRecorder: recorder,
          preflight: RecoveryAgentRegistrationPreflight(bundleURL: bundleURL)
        ),
        evidenceStore: evidenceStore,
        bootSession: try SystemBootSessionIdentifier.current()
      ).prepareForReboot()
    } catch {
      return HostReport(outcome: "bootSessionUnavailable")
    }

    let outcome: String
    if report.registration == .registeredEnabled,
      report.evidenceStatus == .armedOnCurrentBoot
    {
      outcome = "rebootLifecycleArmed"
    } else if report.cleanup != nil {
      outcome = "rebootLifecycleRegistrationCleaned"
    } else {
      outcome = "rebootLifecyclePreparationStopped"
    }
    return HostReport(
      outcome: outcome,
      registration: report.registration,
      unregistration: report.cleanup,
      evidenceStatus: report.evidenceStatus
    )
  }

  private static func runPhaseCUnregistration(
    bundleURL: URL,
    emergency: Bool
  ) -> HostReport {
    let recorder: PersistentActivationAttemptRecorder
    let evidenceStore: RebootDeliveryEvidenceStore
    do {
      guard
        let existingRecorder = try PersistentActivationAttemptRecorder.openExisting(
          session: .rebootLifecycle
        ),
        let existingEvidence = try RebootDeliveryEvidenceStore.openExisting(
          sessionURL: existingRecorder.sessionURL
        )
      else {
        return HostReport(outcome: "ledgerUnavailable")
      }
      recorder = existingRecorder
      evidenceStore = existingEvidence
    } catch {
      return HostReport(outcome: "ledgerUnavailable")
    }

    let sessionLock: LifecycleActivationSessionLock
    do {
      sessionLock = try LifecycleActivationSessionLock(sessionURL: recorder.sessionURL)
    } catch {
      return HostReport(outcome: "sessionBusyOrUnsafe")
    }
    defer { sessionLock.release() }

    do {
      guard try recorder.hasReservation(.registration) else {
        return HostReport(outcome: "ownershipNotEstablished")
      }
    } catch {
      return HostReport(outcome: "ledgerUnavailable")
    }

    let evidenceStatus: RebootDeliveryEvidenceStatus?
    do {
      evidenceStatus = try evidenceStore.status(
        on: SystemBootSessionIdentifier.current()
      )
    } catch {
      return HostReport(outcome: "deliveryEvidenceUnsafe")
    }
    if !emergency, evidenceStatus != .deliveredOnCurrentBoot {
      return HostReport(
        outcome: "deliveryNotProven",
        evidenceStatus: evidenceStatus
      )
    }

    let unregistration = LifecycleActivationController(
      service: RecoveryAgentServiceController(),
      attemptRecorder: recorder,
      preflight: RecoveryAgentRegistrationPreflight(bundleURL: bundleURL)
    ).unregisterAfterRegistrationAttempt()
    return HostReport(
      outcome: emergency
        ? "phaseCEmergencyUnregistrationCompleted"
        : "rebootLifecycleUnregistrationCompleted",
      unregistration: unregistration,
      evidenceStatus: evidenceStatus
    )
  }

  private static func readPhaseCDeliveryStatus() -> HostReport {
    do {
      guard
        let recorder = try PersistentActivationAttemptRecorder.openExisting(
          session: .rebootLifecycle
        ),
        let evidenceStore = try RebootDeliveryEvidenceStore.openExisting(
          sessionURL: recorder.sessionURL
        )
      else {
        return HostReport(outcome: "notPrepared")
      }
      let status = try evidenceStore.status(on: SystemBootSessionIdentifier.current())
      return HostReport(outcome: status.rawValue, evidenceStatus: status)
    } catch {
      return HostReport(outcome: "deliveryEvidenceUnsafe")
    }
  }

  private static func enclosingBundleURL() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0])
      .standardizedFileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func writeJSON(_ report: HostReport) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(report) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
  }
}

private struct HostReport: Codable {
  let outcome: String
  let registration: RegistrationOutcome?
  let unregistration: UnregistrationOutcome?
  let evidenceStatus: RebootDeliveryEvidenceStatus?

  init(
    outcome: String,
    registration: RegistrationOutcome? = nil,
    unregistration: UnregistrationOutcome? = nil,
    evidenceStatus: RebootDeliveryEvidenceStatus? = nil
  ) {
    self.outcome = outcome
    self.registration = registration
    self.unregistration = unregistration
    self.evidenceStatus = evidenceStatus
  }
}
