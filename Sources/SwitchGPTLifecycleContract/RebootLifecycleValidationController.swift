public struct RebootLifecycleValidationReport: Codable, Equatable, Sendable {
  public let registration: RegistrationOutcome
  public let cleanup: UnregistrationOutcome?
  public let evidenceStatus: RebootDeliveryEvidenceStatus?

  public init(
    registration: RegistrationOutcome,
    cleanup: UnregistrationOutcome?,
    evidenceStatus: RebootDeliveryEvidenceStatus?
  ) {
    self.registration = registration
    self.cleanup = cleanup
    self.evidenceStatus = evidenceStatus
  }
}

/// Arms write-once reboot evidence immediately before the single registration call.
/// Any non-enabled result owned by this invocation receives one immediate cleanup attempt.
public final class RebootLifecycleValidationController {
  private enum PreparationError: Error {
    case alreadyArmed
  }

  private let activationController: LifecycleActivationController
  private let evidenceStore: RebootDeliveryEvidenceStore
  private let bootSession: BootSessionIdentifier

  public init(
    activationController: LifecycleActivationController,
    evidenceStore: RebootDeliveryEvidenceStore,
    bootSession: BootSessionIdentifier
  ) {
    self.activationController = activationController
    self.evidenceStore = evidenceStore
    self.bootSession = bootSession
  }

  public func prepareForReboot() -> RebootLifecycleValidationReport {
    let registration = activationController.registerIfNeeded {
      guard try self.evidenceStore.arm(on: self.bootSession) else {
        throw PreparationError.alreadyArmed
      }
    }

    let evidenceStatus = try? evidenceStore.status(on: bootSession)
    let cleanup: UnregistrationOutcome?
    switch registration {
    case .registeredAwaitingApproval, .registrationUnconfirmed:
      cleanup = activationController.unregisterAfterRegistrationAttempt()
    case .registeredEnabled where evidenceStatus != .armedOnCurrentBoot:
      cleanup = activationController.unregisterAfterRegistrationAttempt()
    case .alreadyEnabled, .awaitingApproval, .registeredEnabled,
      .registrationAttemptAlreadyConsumed, .registrationAttemptReservationUnavailable,
      .registrationPreparationFailed, .registrationPreflightFailed, .statusUnavailable:
      cleanup = nil
    }

    return RebootLifecycleValidationReport(
      registration: registration,
      cleanup: cleanup,
      evidenceStatus: evidenceStatus
    )
  }
}
