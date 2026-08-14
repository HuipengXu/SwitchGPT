public enum RecoveryServiceStatus: String, Codable, Equatable, Sendable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
  case unknown
}

public protocol RecoveryServiceControlling: AnyObject {
  func readStatus() throws -> RecoveryServiceStatus
  func register() throws
  func unregister() throws
}

public protocol LifecycleActivationPreflighting {
  func validateForRegistration() throws
}

public enum LifecycleActivationOperation: String, Codable, Equatable, Sendable {
  case registration
  case unregistration
}

/// Implementations must atomically persist the reservation before returning `true`.
public protocol LifecycleActivationAttemptRecording: AnyObject {
  func reserve(_ operation: LifecycleActivationOperation) throws -> Bool
}

public enum RegistrationOutcome: String, Codable, Equatable, Sendable {
  case alreadyEnabled
  case awaitingApproval
  case registeredEnabled
  case registeredAwaitingApproval
  case registrationUnconfirmed
  case registrationAttemptAlreadyConsumed
  case registrationAttemptReservationUnavailable
  case registrationPreparationFailed
  case registrationPreflightFailed
  case statusUnavailable
}

public enum UnregistrationOutcome: String, Codable, Equatable, Sendable {
  case alreadyUnregistered
  case unregistered
  case unregistrationUnconfirmed
  case unregistrationAttemptAlreadyConsumed
  case unregistrationAttemptReservationUnavailable
  case serviceNotFound
  case statusUnavailable
}

/// Coordinates only an explicit caller request. It does not poll, schedule, retry, or open System Settings.
/// The injected durable attempt recorder must permit at most one registration and one unregistration.
public final class LifecycleActivationController {
  private let service: any RecoveryServiceControlling
  private let attemptRecorder: any LifecycleActivationAttemptRecording
  private let preflight: any LifecycleActivationPreflighting

  public init(
    service: any RecoveryServiceControlling,
    attemptRecorder: any LifecycleActivationAttemptRecording,
    preflight: any LifecycleActivationPreflighting
  ) {
    self.service = service
    self.attemptRecorder = attemptRecorder
    self.preflight = preflight
  }

  public func registerIfNeeded() -> RegistrationOutcome {
    registerIfNeeded(beforeRegistration: {})
  }

  /// The preparation hook runs after the durable registration reservation and before the API call.
  /// A failed hook consumes the attempt and prevents system mutation.
  public func registerIfNeeded(
    beforeRegistration: () throws -> Void
  ) -> RegistrationOutcome {
    let initialStatus: RecoveryServiceStatus
    do {
      initialStatus = try service.readStatus()
    } catch {
      return .statusUnavailable
    }

    switch initialStatus {
    case .enabled:
      return .alreadyEnabled
    case .requiresApproval:
      return .awaitingApproval
    case .notFound, .notRegistered:
      do {
        try preflight.validateForRegistration()
      } catch {
        return .registrationPreflightFailed
      }
      do {
        guard try attemptRecorder.reserve(.registration) else {
          return .registrationAttemptAlreadyConsumed
        }
      } catch {
        return .registrationAttemptReservationUnavailable
      }
    case .unknown:
      return .statusUnavailable
    }

    do {
      try beforeRegistration()
    } catch {
      return .registrationPreparationFailed
    }

    do {
      try service.register()
    } catch {
      return observeRegistrationResult()
    }
    return observeRegistrationResult()
  }

  public func unregisterIfNeeded() -> UnregistrationOutcome {
    unregisterIfNeeded(allowNotFoundAfterRegistrationAttempt: false)
  }

  /// Cleanup-only entry for a caller that has durable proof it already invoked registration.
  public func unregisterAfterRegistrationAttempt() -> UnregistrationOutcome {
    unregisterIfNeeded(allowNotFoundAfterRegistrationAttempt: true)
  }

  private func unregisterIfNeeded(
    allowNotFoundAfterRegistrationAttempt: Bool
  ) -> UnregistrationOutcome {
    let initialStatus: RecoveryServiceStatus
    do {
      initialStatus = try service.readStatus()
    } catch {
      guard allowNotFoundAfterRegistrationAttempt else { return .statusUnavailable }
      return reserveAndUnregister()
    }

    switch initialStatus {
    case .notRegistered:
      return .alreadyUnregistered
    case .notFound:
      guard allowNotFoundAfterRegistrationAttempt else { return .serviceNotFound }
      return reserveAndUnregister()
    case .unknown:
      guard allowNotFoundAfterRegistrationAttempt else { return .statusUnavailable }
      return reserveAndUnregister()
    case .enabled, .requiresApproval:
      return reserveAndUnregister()
    }
  }

  private func reserveAndUnregister() -> UnregistrationOutcome {
    do {
      guard try attemptRecorder.reserve(.unregistration) else {
        return .unregistrationAttemptAlreadyConsumed
      }
    } catch {
      return .unregistrationAttemptReservationUnavailable
    }
    do {
      try service.unregister()
    } catch {
      return observeUnregistrationResult()
    }
    return observeUnregistrationResult()
  }

  private func observeRegistrationResult() -> RegistrationOutcome {
    do {
      switch try service.readStatus() {
      case .enabled:
        return .registeredEnabled
      case .requiresApproval:
        return .registeredAwaitingApproval
      case .notRegistered, .notFound:
        return .registrationUnconfirmed
      case .unknown:
        return .registrationUnconfirmed
      }
    } catch {
      return .registrationUnconfirmed
    }
  }

  private func observeUnregistrationResult() -> UnregistrationOutcome {
    do {
      switch try service.readStatus() {
      case .notRegistered:
        return .unregistered
      case .enabled, .requiresApproval, .notFound, .unknown:
        return .unregistrationUnconfirmed
      }
    } catch {
      return .unregistrationUnconfirmed
    }
  }
}
