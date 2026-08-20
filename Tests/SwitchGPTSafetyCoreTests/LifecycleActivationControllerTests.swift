import SwitchGPTLifecycleContract
import XCTest

final class LifecycleActivationControllerTests: XCTestCase {
  func testRegistrationFromNotRegisteredCallsRegisterOnceAndObservesEnabled() {
    let service = FixtureRecoveryService(statuses: [.notRegistered, .enabled])
    let controller = makeController(service: service)

    XCTAssertEqual(controller.registerIfNeeded(), .registeredEnabled)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(service.unregisterCount, 0)
    XCTAssertEqual(service.statusReadCount, 2)
  }

  func testRegistrationThatRequiresApprovalDoesNotRetry() {
    let service = FixtureRecoveryService(statuses: [.notRegistered, .requiresApproval])
    let controller = makeController(service: service)

    XCTAssertEqual(controller.registerIfNeeded(), .registeredAwaitingApproval)
    XCTAssertEqual(controller.registerIfNeeded(), .awaitingApproval)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(service.statusReadCount, 3)
  }

  func testAlreadyEnabledDoesNotRegister() {
    let service = FixtureRecoveryService(statuses: [.enabled])
    let controller = makeController(service: service)

    XCTAssertEqual(controller.registerIfNeeded(), .alreadyEnabled)
    XCTAssertEqual(service.registerCount, 0)
  }

  func testAlreadyAwaitingApprovalDoesNotRegister() {
    let service = FixtureRecoveryService(statuses: [.requiresApproval])
    let controller = makeController(service: service)

    XCTAssertEqual(controller.registerIfNeeded(), .awaitingApproval)
    XCTAssertEqual(service.registerCount, 0)
  }

  func testNotFoundWithFailedPreflightAndUnavailableStatusDoNotRegister() {
    let notFound = FixtureRecoveryService(statuses: [.notFound])
    let failedPreflight = FixtureActivationPreflight(fails: true)
    XCTAssertEqual(
      makeController(service: notFound, preflight: failedPreflight).registerIfNeeded(),
      .registrationPreflightFailed
    )
    XCTAssertEqual(notFound.registerCount, 0)
    XCTAssertEqual(failedPreflight.validationCount, 1)

    let unavailable = FixtureRecoveryService(statuses: [], statusFailures: [1])
    XCTAssertEqual(
      makeController(service: unavailable).registerIfNeeded(),
      .statusUnavailable
    )
    XCTAssertEqual(unavailable.registerCount, 0)
  }

  func testUnknownSystemStatusFailsClosedWithoutMutation() {
    let registrationService = FixtureRecoveryService(statuses: [.unknown])
    XCTAssertEqual(
      makeController(service: registrationService).registerIfNeeded(),
      .statusUnavailable
    )
    XCTAssertEqual(registrationService.registerCount, 0)

    let unregistrationService = FixtureRecoveryService(statuses: [.unknown])
    XCTAssertEqual(
      makeController(service: unregistrationService).unregisterIfNeeded(),
      .statusUnavailable
    )
    XCTAssertEqual(unregistrationService.unregisterCount, 0)
  }

  func testNotFoundWithValidPreflightPermitsOneRegistrationAttempt() {
    let service = FixtureRecoveryService(statuses: [.notFound, .requiresApproval])
    let preflight = FixtureActivationPreflight()
    let controller = makeController(service: service, preflight: preflight)

    XCTAssertEqual(controller.registerIfNeeded(), .registeredAwaitingApproval)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(preflight.validationCount, 1)
  }

  func testFailedPreflightDoesNotConsumeAttemptBudget() {
    let service = FixtureRecoveryService(statuses: [.notRegistered, .notRegistered, .enabled])
    let recorder = FixtureActivationAttemptRecorder()

    XCTAssertEqual(
      makeController(
        service: service,
        recorder: recorder,
        preflight: FixtureActivationPreflight(fails: true)
      ).registerIfNeeded(),
      .registrationPreflightFailed
    )
    XCTAssertEqual(
      makeController(
        service: service,
        recorder: recorder,
        preflight: FixtureActivationPreflight()
      ).registerIfNeeded(),
      .registeredEnabled
    )
    XCTAssertEqual(service.registerCount, 1)
  }

  func testRegistrationPreparationRunsAfterReservationAndBeforeMutation() {
    let service = FixtureRecoveryService(statuses: [.notRegistered, .enabled])
    let recorder = FixtureActivationAttemptRecorder()
    var preparationObservedReservation = false

    let outcome = makeController(service: service, recorder: recorder)
      .registerIfNeeded {
        preparationObservedReservation = recorder.operations == [.registration]
      }

    XCTAssertEqual(outcome, .registeredEnabled)
    XCTAssertTrue(preparationObservedReservation)
    XCTAssertEqual(service.registerCount, 1)
  }

  func testFailedRegistrationPreparationConsumesAttemptWithoutSystemMutation() {
    let service = FixtureRecoveryService(statuses: [.notRegistered, .notRegistered])
    let recorder = FixtureActivationAttemptRecorder()
    let controller = makeController(service: service, recorder: recorder)

    XCTAssertEqual(
      controller.registerIfNeeded { throw FixtureServiceError.injected },
      .registrationPreparationFailed
    )
    XCTAssertEqual(controller.registerIfNeeded(), .registrationAttemptAlreadyConsumed)
    XCTAssertEqual(service.registerCount, 0)
  }

  func testRegistrationErrorUsesOneObservationAndRecognizesApprovalState() {
    let service = FixtureRecoveryService(
      statuses: [.notRegistered, .requiresApproval],
      registerFails: true
    )
    let controller = makeController(service: service)

    XCTAssertEqual(controller.registerIfNeeded(), .registeredAwaitingApproval)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(service.statusReadCount, 2)
  }

  func testFailedRegistrationConsumesAttemptAndNeverRetries() {
    let service = FixtureRecoveryService(
      statuses: [.notRegistered, .notRegistered, .notRegistered],
      registerFails: true
    )
    let controller = makeController(service: service)

    XCTAssertEqual(controller.registerIfNeeded(), .registrationUnconfirmed)
    XCTAssertEqual(controller.registerIfNeeded(), .registrationAttemptAlreadyConsumed)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(service.statusReadCount, 3)
  }

  func testPostRegistrationStatusFailureStopsWithoutRetry() {
    let service = FixtureRecoveryService(
      statuses: [.notRegistered],
      statusFailures: [2]
    )
    let controller = makeController(service: service)

    XCTAssertEqual(controller.registerIfNeeded(), .registrationUnconfirmed)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(service.statusReadCount, 2)
  }

  func testUnregistrationFromEnabledCallsUnregisterOnceAndObservesTerminalState() {
    let service = FixtureRecoveryService(statuses: [.enabled, .notRegistered])
    let controller = makeController(service: service)

    XCTAssertEqual(controller.unregisterIfNeeded(), .unregistered)
    XCTAssertEqual(service.unregisterCount, 1)
    XCTAssertEqual(service.registerCount, 0)
    XCTAssertEqual(service.statusReadCount, 2)
  }

  func testUnregistrationFromApprovalStateIsAllowedOnce() {
    let service = FixtureRecoveryService(statuses: [.requiresApproval, .notRegistered])
    let controller = makeController(service: service)

    XCTAssertEqual(controller.unregisterIfNeeded(), .unregistered)
    XCTAssertEqual(service.unregisterCount, 1)
  }

  func testAlreadyUnregisteredAndNotFoundDoNotUnregister() {
    let unregistered = FixtureRecoveryService(statuses: [.notRegistered])
    XCTAssertEqual(
      makeController(service: unregistered).unregisterIfNeeded(),
      .alreadyUnregistered
    )
    XCTAssertEqual(unregistered.unregisterCount, 0)

    let notFound = FixtureRecoveryService(statuses: [.notFound])
    XCTAssertEqual(
      makeController(service: notFound).unregisterIfNeeded(),
      .serviceNotFound
    )
    XCTAssertEqual(notFound.unregisterCount, 0)
  }

  func testFailedUnregistrationConsumesAttemptAndNeverRetries() {
    let service = FixtureRecoveryService(
      statuses: [.enabled, .enabled, .enabled],
      unregisterFails: true
    )
    let controller = makeController(service: service)

    XCTAssertEqual(controller.unregisterIfNeeded(), .unregistrationUnconfirmed)
    XCTAssertEqual(controller.unregisterIfNeeded(), .unregistrationAttemptAlreadyConsumed)
    XCTAssertEqual(service.unregisterCount, 1)
    XCTAssertEqual(service.statusReadCount, 3)
  }

  func testPostUnregistrationStatusFailureStopsWithoutRetry() {
    let service = FixtureRecoveryService(
      statuses: [.enabled],
      statusFailures: [2]
    )
    let controller = makeController(service: service)

    XCTAssertEqual(controller.unregisterIfNeeded(), .unregistrationUnconfirmed)
    XCTAssertEqual(service.unregisterCount, 1)
    XCTAssertEqual(service.statusReadCount, 2)
  }

  func testRegistrationReservationSurvivesControllerReplacement() {
    let service = FixtureRecoveryService(
      statuses: [.notRegistered, .notRegistered, .notRegistered],
      registerFails: true
    )
    let recorder = FixtureActivationAttemptRecorder()

    XCTAssertEqual(
      makeController(service: service, recorder: recorder).registerIfNeeded(),
      .registrationUnconfirmed
    )
    XCTAssertEqual(
      makeController(service: service, recorder: recorder).registerIfNeeded(),
      .registrationAttemptAlreadyConsumed
    )
    XCTAssertEqual(service.registerCount, 1)
  }

  func testUnregistrationReservationSurvivesControllerReplacement() {
    let service = FixtureRecoveryService(
      statuses: [.enabled, .enabled, .enabled],
      unregisterFails: true
    )
    let recorder = FixtureActivationAttemptRecorder()

    XCTAssertEqual(
      makeController(service: service, recorder: recorder).unregisterIfNeeded(),
      .unregistrationUnconfirmed
    )
    XCTAssertEqual(
      makeController(service: service, recorder: recorder).unregisterIfNeeded(),
      .unregistrationAttemptAlreadyConsumed
    )
    XCTAssertEqual(service.unregisterCount, 1)
  }

  func testRecorderFailureStopsBeforeSystemMutation() {
    let registrationService = FixtureRecoveryService(statuses: [.notRegistered])
    let registrationRecorder = FixtureActivationAttemptRecorder(fails: true)
    XCTAssertEqual(
      makeController(service: registrationService, recorder: registrationRecorder)
        .registerIfNeeded(),
      .registrationAttemptReservationUnavailable
    )
    XCTAssertEqual(registrationService.registerCount, 0)

    let unregistrationService = FixtureRecoveryService(statuses: [.enabled])
    let unregistrationRecorder = FixtureActivationAttemptRecorder(fails: true)
    XCTAssertEqual(
      makeController(service: unregistrationService, recorder: unregistrationRecorder)
        .unregisterIfNeeded(),
      .unregistrationAttemptReservationUnavailable
    )
    XCTAssertEqual(unregistrationService.unregisterCount, 0)
  }

  func testImmediateLifecycleRegistersAndImmediatelyUnregisters() {
    let service = FixtureRecoveryService(
      statuses: [.notRegistered, .enabled, .enabled, .notRegistered]
    )
    let report = ImmediateLifecycleValidationController(
      activationController: makeController(service: service)
    ).run()

    XCTAssertEqual(report.registration, .registeredEnabled)
    XCTAssertEqual(report.unregistration, .unregistered)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(service.unregisterCount, 1)
  }

  func testImmediateLifecycleCleansUpApprovalAndAmbiguousStates() {
    let approvalService = FixtureRecoveryService(
      statuses: [.notRegistered, .requiresApproval, .requiresApproval, .notRegistered]
    )
    let approvalReport = ImmediateLifecycleValidationController(
      activationController: makeController(service: approvalService)
    ).run()
    XCTAssertEqual(approvalReport.registration, .registeredAwaitingApproval)
    XCTAssertEqual(approvalReport.unregistration, .unregistered)
    XCTAssertEqual(approvalService.unregisterCount, 1)

    let ambiguousService = FixtureRecoveryService(
      statuses: [.notRegistered, .notFound, .notFound, .notRegistered],
      registerFails: true
    )
    let ambiguousReport = ImmediateLifecycleValidationController(
      activationController: makeController(service: ambiguousService)
    ).run()
    XCTAssertEqual(ambiguousReport.registration, .registrationUnconfirmed)
    XCTAssertEqual(ambiguousReport.unregistration, .unregistered)
    XCTAssertEqual(ambiguousService.unregisterCount, 1)
  }

  func testImmediateLifecycleDoesNotUnregisterPreexistingService() {
    let enabledService = FixtureRecoveryService(statuses: [.enabled])
    let enabledReport = ImmediateLifecycleValidationController(
      activationController: makeController(service: enabledService)
    ).run()
    XCTAssertEqual(enabledReport.registration, .alreadyEnabled)
    XCTAssertNil(enabledReport.unregistration)
    XCTAssertEqual(enabledService.unregisterCount, 0)

    let approvalService = FixtureRecoveryService(statuses: [.requiresApproval])
    let approvalReport = ImmediateLifecycleValidationController(
      activationController: makeController(service: approvalService)
    ).run()
    XCTAssertEqual(approvalReport.registration, .awaitingApproval)
    XCTAssertNil(approvalReport.unregistration)
    XCTAssertEqual(approvalService.unregisterCount, 0)
  }

  func testOwnedCleanupMayUnregisterFromNotFoundExactlyOnce() {
    let service = FixtureRecoveryService(statuses: [.notFound, .notRegistered])
    let controller = makeController(service: service)

    XCTAssertEqual(controller.unregisterAfterRegistrationAttempt(), .unregistered)
    XCTAssertEqual(service.unregisterCount, 1)
    XCTAssertEqual(controller.unregisterAfterRegistrationAttempt(), .alreadyUnregistered)
    XCTAssertEqual(service.unregisterCount, 1)
  }

  func testOwnedCleanupUnregistersWhenStatusIsUnavailableOrUnknown() {
    let unavailable = FixtureRecoveryService(
      statuses: [.notRegistered],
      statusFailures: [1]
    )
    XCTAssertEqual(
      makeController(service: unavailable).unregisterAfterRegistrationAttempt(),
      .unregistrationUnconfirmed
    )
    XCTAssertEqual(unavailable.unregisterCount, 1)

    let unknown = FixtureRecoveryService(statuses: [.unknown, .notRegistered])
    XCTAssertEqual(
      makeController(service: unknown).unregisterAfterRegistrationAttempt(),
      .unregistered
    )
    XCTAssertEqual(unknown.unregisterCount, 1)
  }

  private func makeController(
    service: FixtureRecoveryService,
    recorder: FixtureActivationAttemptRecorder = FixtureActivationAttemptRecorder(),
    preflight: FixtureActivationPreflight = FixtureActivationPreflight()
  ) -> LifecycleActivationController {
    LifecycleActivationController(
      service: service,
      attemptRecorder: recorder,
      preflight: preflight
    )
  }
}

private enum FixtureServiceError: Error {
  case injected
}

private final class FixtureRecoveryService: RecoveryServiceControlling {
  private let statuses: [RecoveryServiceStatus]
  private let statusFailures: Set<Int>
  private let registerFails: Bool
  private let unregisterFails: Bool
  private var lastStatus: RecoveryServiceStatus = .notFound

  private(set) var statusReadCount = 0
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  init(
    statuses: [RecoveryServiceStatus],
    statusFailures: Set<Int> = [],
    registerFails: Bool = false,
    unregisterFails: Bool = false
  ) {
    self.statuses = statuses
    self.statusFailures = statusFailures
    self.registerFails = registerFails
    self.unregisterFails = unregisterFails
  }

  func readStatus() throws -> RecoveryServiceStatus {
    statusReadCount += 1
    if statusFailures.contains(statusReadCount) {
      throw FixtureServiceError.injected
    }
    if statusReadCount <= statuses.count {
      lastStatus = statuses[statusReadCount - 1]
    }
    return lastStatus
  }

  func register() throws {
    registerCount += 1
    if registerFails {
      throw FixtureServiceError.injected
    }
  }

  func unregister() throws {
    unregisterCount += 1
    if unregisterFails {
      throw FixtureServiceError.injected
    }
  }
}

private final class FixtureActivationAttemptRecorder: LifecycleActivationAttemptRecording {
  private let fails: Bool
  private(set) var operations: Set<LifecycleActivationOperation> = []

  init(fails: Bool = false) {
    self.fails = fails
  }

  func reserve(_ operation: LifecycleActivationOperation) throws -> Bool {
    if fails {
      throw FixtureServiceError.injected
    }
    return operations.insert(operation).inserted
  }
}

private final class FixtureActivationPreflight: LifecycleActivationPreflighting {
  private let fails: Bool
  private(set) var validationCount = 0

  init(fails: Bool = false) {
    self.fails = fails
  }

  func validateForRegistration() throws {
    validationCount += 1
    if fails {
      throw FixtureServiceError.injected
    }
  }
}
