public struct ImmediateLifecycleValidationReport: Codable, Equatable, Sendable {
  public let registration: RegistrationOutcome
  public let unregistration: UnregistrationOutcome?

  public init(
    registration: RegistrationOutcome,
    unregistration: UnregistrationOutcome?
  ) {
    self.registration = registration
    self.unregistration = unregistration
  }
}

/// Runs one explicit registration attempt and, only when this invocation may have
/// registered the service, immediately spends the independent unregistration budget.
public struct ImmediateLifecycleValidationController {
  private let activationController: LifecycleActivationController

  public init(activationController: LifecycleActivationController) {
    self.activationController = activationController
  }

  public func run() -> ImmediateLifecycleValidationReport {
    let registration = activationController.registerIfNeeded()
    let shouldAttemptCleanup: Bool
    switch registration {
    case .registeredEnabled, .registeredAwaitingApproval, .registrationUnconfirmed:
      shouldAttemptCleanup = true
    case .alreadyEnabled, .awaitingApproval, .registrationAttemptAlreadyConsumed,
      .registrationAttemptReservationUnavailable, .registrationPreflightFailed,
      .registrationPreparationFailed, .statusUnavailable:
      shouldAttemptCleanup = false
    }
    return ImmediateLifecycleValidationReport(
      registration: registration,
      unregistration: shouldAttemptCleanup
        ? activationController.unregisterAfterRegistrationAttempt()
        : nil
    )
  }
}
