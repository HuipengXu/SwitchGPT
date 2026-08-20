import Foundation
import SwitchGPTSafetyCore

/// Concrete transaction adapter boundary for complete ChatGPT Desktop switching.
/// This target is intentionally not linked by the default UI until the real gate is authorized.
public final class RealChatGPTDesktopAdapter: TransactionDesktop {
  private let sourceIdentity: IdentityID
  private let profilesByIdentity: [IdentityID: DesktopCredentialProfile]
  private let processController: DesktopProcessControlling
  private let identityReader: InstalledIdentityReading
  private let authenticationInstaller: AuthenticationStateInstalling

  public init(
    sourceIdentity: IdentityID,
    profiles: [DesktopCredentialProfile],
    processController: DesktopProcessControlling,
    identityReader: InstalledIdentityReading,
    authenticationInstaller: AuthenticationStateInstalling
  ) throws {
    var profilesByIdentity: [IdentityID: DesktopCredentialProfile] = [:]
    for profile in profiles {
      guard profilesByIdentity.updateValue(profile, forKey: profile.identity) == nil else {
        throw DesktopIntegrationError.duplicateProfile
      }
    }
    guard profilesByIdentity[sourceIdentity] != nil else {
      throw DesktopIntegrationError.missingProfile
    }
    self.sourceIdentity = sourceIdentity
    self.profilesByIdentity = profilesByIdentity
    self.processController = processController
    self.identityReader = identityReader
    self.authenticationInstaller = authenticationInstaller
  }

  public func isRunning() throws -> Bool {
    try processController.isRunning()
  }

  public func currentIdentity() throws -> IdentityID {
    try identityReader.currentIdentity()
  }

  public func stop() throws {
    try processController.terminateAndWait()
  }

  public func install(identity: IdentityID) throws {
    if identity == sourceIdentity {
      if try authenticationInstaller.hasRecoverySnapshot() {
        try authenticationInstaller.restoreRecoverySnapshot()
        return
      }
      guard try identityReader.currentIdentity() == sourceIdentity else {
        throw DesktopIntegrationError.missingRecoverySnapshot
      }
      return
    }

    guard let profile = profilesByIdentity[identity] else {
      throw DesktopIntegrationError.missingProfile
    }
    try authenticationInstaller.snapshotActiveStateIfNeeded()
    try authenticationInstaller.installAuthenticationFile(
      from: profile.authenticationFileURL
    )
    guard try identityReader.currentIdentity() == identity else {
      throw DesktopIntegrationError.identityMismatch
    }
  }

  public func start() throws {
    try processController.launchAndWait()
  }
}
