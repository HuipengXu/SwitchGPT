import Darwin
import Foundation
import Security
import SwitchGPTAppCore
import SwitchGPTDesktopIntegration
import SwitchGPTSafetyCore

struct RealSwitchPlan: Sendable, Identifiable {
  let id = UUID()
  let sourceAccount: AccountRecord
  let targetAccount: AccountRecord
  fileprivate let sourceIdentity: IdentityID
  fileprivate let targetIdentity: IdentityID
  fileprivate let sourceAuthenticationURL: URL
  fileprivate let targetAuthenticationURL: URL
  fileprivate let expectedHostTeamIdentifier: String
  fileprivate let helperURL: URL
  let targetApplicationCompatibility: ChatGPTDesktopCompatibilityAssessment
}

enum RealSwitchOutcome: Sendable {
  case committed
  case rolledBack
  case manualRecoveryRequired
}

struct RealSwitchResult: Sendable {
  let outcome: RealSwitchOutcome
  let receiptRecorded: Bool
}

enum ExperimentalRealSwitchError: Error, LocalizedError, Sendable {
  case unsignedHost
  case invalidTargetApplication
  case targetApplicationChanged
  case activeAccountNotConfigured
  case activeAccountNotPreserved
  case targetAccountChanged
  case sourceAndTargetMatch
  case insecureStorage
  case recoveryHelperFailed
  case switchFailed

  var errorDescription: String? {
    switch self {
    case .unsignedHost:
      return "This build is not signed for experimental switching."
    case .invalidTargetApplication:
      return "The installed ChatGPT app could not be verified."
    case .targetApplicationChanged:
      return "ChatGPT changed after confirmation. Review and confirm the switch again."
    case .activeAccountNotConfigured:
      return "The account currently active in ChatGPT is not configured in SwitchGPT."
    case .activeAccountNotPreserved:
      return "SwitchGPT must first preserve the active account in private storage."
    case .targetAccountChanged:
      return "The selected account credentials no longer match the pinned account."
    case .sourceAndTargetMatch:
      return "ChatGPT is already using this account."
    case .insecureStorage:
      return "SwitchGPT could not create private recovery storage."
    case .recoveryHelperFailed:
      return "The independent recovery process could not be verified or completed."
    case .switchFailed:
      return "The switch did not complete; SwitchGPT attempted to restore the original account."
    }
  }
}

enum ExperimentalRealSwitchCoordinator {
  private static let hostBundleIdentifier = "com.kunpeng.SwitchGPT"
  private static let targetBundleIdentifier = "com.openai.codex"
  private static let targetTeamIdentifier = "2DC432GLL2"
  private static let failureInjectionInfoKey = "SwitchGPTInjectTargetVerificationFailureOnce"
  private static let targetApplicationURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
  private static let failureInjectionLock = NSLock()
  private nonisolated(unsafe) static var failureInjectionConsumed = false

  static func preflight(
    target: AccountRecord,
    accounts: [AccountRecord],
    bundle: Bundle = .main
  ) throws -> RealSwitchPlan {
    guard
      let expectedTeam = bundle.object(
        forInfoDictionaryKey: "SwitchGPTHostTeamIdentifier"
      ) as? String, !expectedTeam.isEmpty
    else {
      throw ExperimentalRealSwitchError.unsignedHost
    }
    let targetApplicationCompatibility = try validateTargetApplication()

    let activeAuthenticationURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("auth.json")
    let sourceIdentity = try PinnedAuthenticationIdentityReader(
      authenticationFileURL: activeAuthenticationURL
    ).currentIdentity()
    guard
      let sourceAccount = accounts.first(where: {
        $0.identityHash == sourceIdentity.rawValue && Self.authenticationURL(for: $0) != nil
      }), let sourceAuthenticationURL = authenticationURL(for: sourceAccount)
    else {
      throw ExperimentalRealSwitchError.activeAccountNotConfigured
    }
    guard sourceAuthenticationURL.standardizedFileURL != activeAuthenticationURL.standardizedFileURL
    else {
      throw ExperimentalRealSwitchError.activeAccountNotPreserved
    }
    guard let targetHash = target.identityHash,
      let targetIdentity = IdentityID(rawValue: targetHash),
      let targetAuthenticationURL = authenticationURL(for: target)
    else {
      throw ExperimentalRealSwitchError.targetAccountChanged
    }
    guard targetAuthenticationURL.standardizedFileURL != activeAuthenticationURL.standardizedFileURL
    else {
      throw ExperimentalRealSwitchError.activeAccountNotPreserved
    }
    guard sourceIdentity != targetIdentity else {
      throw ExperimentalRealSwitchError.sourceAndTargetMatch
    }
    guard
      try PinnedAuthenticationIdentityReader(
        authenticationFileURL: targetAuthenticationURL
      ).currentIdentity() == targetIdentity
    else {
      throw ExperimentalRealSwitchError.targetAccountChanged
    }

    let helperURL = bundle.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Helpers", isDirectory: true)
      .appendingPathComponent("SwitchGPTRecoverySupervisor")
    try EmbeddedRecoveryHelperContract.validate(
      helperURL: helperURL,
      expectedTeamIdentifier: expectedTeam,
      expectedSigningIdentifier: "SwitchGPTRecoverySupervisor"
    )

    return RealSwitchPlan(
      sourceAccount: sourceAccount,
      targetAccount: target,
      sourceIdentity: sourceIdentity,
      targetIdentity: targetIdentity,
      sourceAuthenticationURL: sourceAuthenticationURL,
      targetAuthenticationURL: targetAuthenticationURL,
      expectedHostTeamIdentifier: expectedTeam,
      helperURL: helperURL,
      targetApplicationCompatibility: targetApplicationCompatibility
    )
  }

  static func perform(_ plan: RealSwitchPlan, bundle: Bundle = .main) throws
    -> RealSwitchResult
  {
    guard try validateTargetApplication() == plan.targetApplicationCompatibility else {
      throw ExperimentalRealSwitchError.targetApplicationChanged
    }

    let transactionDirectory = try makeTransactionDirectory()
    let store = try TransactionStore(directoryURL: transactionDirectory)
    let activeAuthenticationURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("auth.json")
    let installer = try SecureAuthenticationFileInstaller(
      activeAuthenticationURL: activeAuthenticationURL,
      recoverySnapshotURL: transactionDirectory.appendingPathComponent("recovery-auth.json")
    )
    try SecureAuthenticationFileInstaller.synchronizePrivateAuthenticationFile(
      from: activeAuthenticationURL,
      to: plan.sourceAuthenticationURL
    )
    guard
      try PinnedAuthenticationIdentityReader(
        authenticationFileURL: plan.sourceAuthenticationURL
      ).currentIdentity() == plan.sourceIdentity
    else {
      throw ExperimentalRealSwitchError.activeAccountNotPreserved
    }
    let baseIdentityReader = PinnedAuthenticationIdentityReader(
      authenticationFileURL: activeAuthenticationURL
    )
    let identityReader: InstalledIdentityReading =
      consumeFailureInjectionIfEnabled(bundle: bundle)
      ? OneShotTargetVerificationFailureReader(
        base: baseIdentityReader,
        targetIdentity: plan.targetIdentity
      ) : baseIdentityReader
    let adapter = try RealChatGPTDesktopAdapter(
      sourceIdentity: plan.sourceIdentity,
      profiles: [
        DesktopCredentialProfile(
          identity: plan.sourceIdentity,
          authenticationFileURL: plan.sourceAuthenticationURL
        ),
        DesktopCredentialProfile(
          identity: plan.targetIdentity,
          authenticationFileURL: plan.targetAuthenticationURL
        ),
      ],
      processController: MacOSChatGPTProcessController(),
      identityReader: identityReader,
      authenticationInstaller: installer
    )
    let hostEvidence = try SystemSupervisorHostEvidenceCollector.collect(
      configuration: SupervisorHostConfiguration(
        expectedHostBundleIdentifier: hostBundleIdentifier,
        expectedHostTeamIdentifier: plan.expectedHostTeamIdentifier,
        targetBundleIdentifier: targetBundleIdentifier,
        targetBundleURL: targetApplicationURL
      ),
      bundle: bundle
    )
    let recoverySupervisor = ProcessOneShotRecoverySupervisor(
      helperURL: plan.helperURL,
      transactionDirectoryURL: transactionDirectory,
      expectedTeamIdentifier: plan.expectedHostTeamIdentifier
    )
    let record = try IndependentDesktopSwitchRunner.perform(
      store: store,
      desktop: adapter,
      hostEvidence: hostEvidence,
      recoverySupervisor: recoverySupervisor,
      source: plan.sourceIdentity,
      target: plan.targetIdentity
    )

    do {
      try recoverySupervisor.waitUntilFinished()
    } catch {
      throw ExperimentalRealSwitchError.recoveryHelperFailed
    }

    let outcome: RealSwitchOutcome
    let receiptOutcome: RealSwitchReceiptOutcome
    switch record.phase {
    case .committed:
      outcome = .committed
      receiptOutcome = .committed
    case .rolledBack:
      outcome = .rolledBack
      receiptOutcome = .rolledBack
    case .manualRecoveryRequired:
      outcome = .manualRecoveryRequired
      receiptOutcome = .manualRecoveryRequired
    default:
      throw ExperimentalRealSwitchError.switchFailed
    }

    let finalIdentityHash = try? baseIdentityReader.currentIdentity().rawValue
    let receipt = RealSwitchReceipt(
      id: record.id,
      sourceIdentityHash: record.sourceIdentity.rawValue,
      targetIdentityHash: record.targetIdentity.rawValue,
      outcome: receiptOutcome,
      finalIdentityHash: finalIdentityHash,
      targetLaunchAttempts: record.targetLaunchAttempts,
      rollbackLaunchAttempts: record.rollbackLaunchAttempts,
      targetWasInstalled: record.targetWasInstalled,
      failureReason: record.failureReason.flatMap {
        RealSwitchReceiptFailureReason(rawValue: $0.rawValue)
      },
      transactionCreatedAt: record.createdAt
    )
    let receiptRecorded = (try? RealSwitchReceiptStore.defaultStore.save(receipt)) != nil

    if record.phase != .manualRecoveryRequired {
      try? FileManager.default.removeItem(at: transactionDirectory)
    }
    return RealSwitchResult(outcome: outcome, receiptRecorded: receiptRecorded)
  }

  private static func authenticationURL(for account: AccountRecord) -> URL? {
    guard case .codexHome(let path) = account.source else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
      .appendingPathComponent("auth.json")
      .standardizedFileURL
  }

  private static func validateTargetApplication() throws -> ChatGPTDesktopCompatibilityAssessment {
    guard let targetBundle = Bundle(url: targetApplicationURL),
      targetBundle.bundleIdentifier == targetBundleIdentifier
    else {
      throw ExperimentalRealSwitchError.invalidTargetApplication
    }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(targetApplicationURL as CFURL, [], &code) == errSecSuccess,
      let code,
      SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
        == errSecSuccess
    else {
      throw ExperimentalRealSwitchError.invalidTargetApplication
    }
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &information
      ) == errSecSuccess,
      let values = information as? [CFString: Any],
      values[kSecCodeInfoTeamIdentifier] as? String == targetTeamIdentifier,
      values[kSecCodeInfoIdentifier] as? String == targetBundleIdentifier
    else {
      throw ExperimentalRealSwitchError.invalidTargetApplication
    }
    return ChatGPTDesktopCompatibility.assessment(
      version: targetBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      build: targetBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    )
  }

  private static func consumeFailureInjectionIfEnabled(bundle: Bundle) -> Bool {
    guard bundle.object(forInfoDictionaryKey: failureInjectionInfoKey) as? Bool == true else {
      return false
    }
    return failureInjectionLock.withLock {
      guard !failureInjectionConsumed else { return false }
      failureInjectionConsumed = true
      return true
    }
  }

  private static func makeTransactionDirectory() throws -> URL {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw ExperimentalRealSwitchError.insecureStorage
    }
    let appRoot = applicationSupport.appendingPathComponent("SwitchGPT", isDirectory: true)
    let transactionsRoot = appRoot.appendingPathComponent("Transactions", isDirectory: true)
    do {
      try preparePrivateDirectory(appRoot)
      try preparePrivateDirectory(transactionsRoot)
      let existingTransactions = try FileManager.default.contentsOfDirectory(
        at: transactionsRoot,
        includingPropertiesForKeys: nil,
        options: []
      )
      guard existingTransactions.isEmpty else {
        throw ExperimentalRealSwitchError.insecureStorage
      }
      let transaction = transactionsRoot.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: transaction,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try RecoveryTransactionPathContract.validateExistingPrivateDirectory(transaction)
      return transaction
    } catch {
      throw ExperimentalRealSwitchError.insecureStorage
    }
  }

  private static func preparePrivateDirectory(_ url: URL) throws {
    var status = stat()
    if url.path.withCString({ lstat($0, &status) }) == 0 {
      guard status.st_mode & S_IFMT == S_IFDIR,
        status.st_uid == geteuid(),
        status.st_mode & 0o777 == 0o700
      else {
        throw ExperimentalRealSwitchError.insecureStorage
      }
      return
    }
    guard errno == ENOENT else { throw ExperimentalRealSwitchError.insecureStorage }
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
  }
}

/// Enabled only by a separately signed local validation bundle. The normal and Release
/// Info.plists do not contain the opt-in key. The first installed target observation succeeds;
/// the second (post-launch verification) returns a synthetic mismatch exactly once.
private final class OneShotTargetVerificationFailureReader: InstalledIdentityReading {
  private let base: InstalledIdentityReading
  private let targetIdentity: IdentityID
  private let lock = NSLock()
  private var targetObservations = 0
  private var injected = false

  init(base: InstalledIdentityReading, targetIdentity: IdentityID) {
    self.base = base
    self.targetIdentity = targetIdentity
  }

  func currentIdentity() throws -> IdentityID {
    let actual = try base.currentIdentity()
    return lock.withLock {
      guard actual == targetIdentity else { return actual }
      targetObservations += 1
      guard targetObservations >= 2, !injected else { return actual }
      injected = true
      return IdentityID(rawValue: "switchgpt-injected-verification-failure")!
    }
  }
}
