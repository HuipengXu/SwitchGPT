import Foundation

public enum SupervisorLaunchMechanism: String, Codable, Sendable {
  case application
  case recoveryService
  case submittedJob
  case embeddedDevelopmentHost
  case unknown
}

public enum SupervisorSignatureEvidence: Equatable, Sendable {
  case verified(teamIdentifier: String, signingIdentifier: String)
  case invalid
}

public struct SupervisorHostEvidence: Equatable, Sendable {
  public let hostBundleIdentifier: String
  public let expectedHostBundleIdentifier: String
  public let targetBundleIdentifier: String
  public let expectedHostTeamIdentifier: String
  public let signatureEvidence: SupervisorSignatureEvidence
  public let executableURL: URL
  public let expectedHostBundleURL: URL
  public let targetBundleURL: URL
  public let ancestorExecutableURLs: [URL]
  public let launchMechanism: SupervisorLaunchMechanism

  public init(
    hostBundleIdentifier: String,
    expectedHostBundleIdentifier: String,
    targetBundleIdentifier: String,
    expectedHostTeamIdentifier: String,
    signatureEvidence: SupervisorSignatureEvidence,
    executableURL: URL,
    expectedHostBundleURL: URL,
    targetBundleURL: URL,
    ancestorExecutableURLs: [URL],
    launchMechanism: SupervisorLaunchMechanism
  ) {
    self.hostBundleIdentifier = hostBundleIdentifier
    self.expectedHostBundleIdentifier = expectedHostBundleIdentifier
    self.targetBundleIdentifier = targetBundleIdentifier
    self.expectedHostTeamIdentifier = expectedHostTeamIdentifier
    self.signatureEvidence = signatureEvidence
    self.executableURL = executableURL
    self.expectedHostBundleURL = expectedHostBundleURL
    self.targetBundleURL = targetBundleURL
    self.ancestorExecutableURLs = ancestorExecutableURLs
    self.launchMechanism = launchMechanism
  }
}

public enum SupervisorSafetyError: Error, Equatable, Sendable {
  case prohibitedLaunchMechanism
  case unexpectedHostIdentity
  case invalidHostSignature
  case executableOutsideExpectedHost
  case hostNestedInsideTarget
  case targetHostedAncestor
  case recoverySupervisorAlreadyArmed
}

public enum IndependentSupervisorHostContract {
  public static func validateInteractiveSwitch(_ evidence: SupervisorHostEvidence) throws {
    guard evidence.launchMechanism == .application else {
      throw SupervisorSafetyError.prohibitedLaunchMechanism
    }
    guard
      !evidence.hostBundleIdentifier.isEmpty,
      evidence.hostBundleIdentifier == evidence.expectedHostBundleIdentifier,
      evidence.hostBundleIdentifier != evidence.targetBundleIdentifier
    else {
      throw SupervisorSafetyError.unexpectedHostIdentity
    }
    guard
      case .verified(let teamIdentifier, let signingIdentifier) = evidence.signatureEvidence,
      !evidence.expectedHostTeamIdentifier.isEmpty,
      teamIdentifier == evidence.expectedHostTeamIdentifier,
      signingIdentifier == evidence.expectedHostBundleIdentifier
    else {
      throw SupervisorSafetyError.invalidHostSignature
    }

    let executable = normalized(evidence.executableURL)
    let hostBundle = normalized(evidence.expectedHostBundleURL)
    let targetBundle = normalized(evidence.targetBundleURL)
    guard isDescendant(executable, of: hostBundle) else {
      throw SupervisorSafetyError.executableOutsideExpectedHost
    }
    guard !isDescendant(hostBundle, of: targetBundle), hostBundle != targetBundle else {
      throw SupervisorSafetyError.hostNestedInsideTarget
    }
    guard
      !evidence.ancestorExecutableURLs.map(normalized).contains(where: {
        $0 == targetBundle || isDescendant($0, of: targetBundle)
      })
    else {
      throw SupervisorSafetyError.targetHostedAncestor
    }
  }

  private static func normalized(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath()
  }

  private static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
    let ancestorComponents = ancestor.pathComponents
    let candidateComponents = candidate.pathComponents
    return candidateComponents.count > ancestorComponents.count
      && Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
  }
}

public protocol OneShotRecoverySupervisor: AnyObject {
  /// Returns only after the recovery-only process is running and waiting for the transaction lock.
  func armAndWaitUntilReady() throws
}

/// The only supported entry point for a future real interactive switch adapter.
///
/// It proves that the transaction runs from an independent application and arms a recovery-only
/// process after durable preparation but before the first desktop lifecycle side effect.
public final class IndependentSwitchSupervisor {
  public typealias CheckpointHandler = (SafetyCheckpoint) throws -> Void

  private let store: TransactionStore
  private let desktop: TransactionDesktop
  private let hostEvidence: SupervisorHostEvidence
  private let recoverySupervisor: OneShotRecoverySupervisor
  private let checkpointHandler: CheckpointHandler

  public init(
    store: TransactionStore,
    desktop: TransactionDesktop,
    hostEvidence: SupervisorHostEvidence,
    recoverySupervisor: OneShotRecoverySupervisor,
    checkpointHandler: @escaping CheckpointHandler = { _ in }
  ) {
    self.store = store
    self.desktop = desktop
    self.hostEvidence = hostEvidence
    self.recoverySupervisor = recoverySupervisor
    self.checkpointHandler = checkpointHandler
  }

  @discardableResult
  public func beginSwitch(from source: IdentityID, to target: IdentityID) throws
    -> TransactionRecord
  {
    try IndependentSupervisorHostContract.validateInteractiveSwitch(hostEvidence)
    var recoveryWasArmed = false
    let engine = SwitchTransactionEngine(store: store, desktop: desktop) {
      [recoverySupervisor] point in
      if point == .afterPrepared {
        guard !recoveryWasArmed else {
          throw SupervisorSafetyError.recoverySupervisorAlreadyArmed
        }
        try recoverySupervisor.armAndWaitUntilReady()
        recoveryWasArmed = true
      }
      try self.checkpointHandler(point)
    }
    return try engine.beginSwitch(from: source, to: target)
  }
}
