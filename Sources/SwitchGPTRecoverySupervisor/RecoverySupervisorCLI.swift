import Foundation
import SwitchGPTDesktopIntegration
import SwitchGPTSafetyCore

@main
enum RecoverySupervisorCLI {
  private static let command = "recover-current"

  static func main() {
    do {
      try run(arguments: Array(CommandLine.arguments.dropFirst()))
      exit(0)
    } catch {
      FileHandle.standardError.write(Data("recovery_supervisor_failed\n".utf8))
      exit(1)
    }
  }

  private static func run(arguments: [String]) throws {
    guard arguments.count == 2, arguments[0] == command else {
      throw RecoverySupervisorError.invalidTransactionPath
    }
    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory
    let transactionsRoot =
      applicationSupport
      .appendingPathComponent("SwitchGPT", isDirectory: true)
      .appendingPathComponent("Transactions", isDirectory: true)
    let candidateDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
      .standardizedFileURL
    try RecoveryTransactionPathContract.validateExistingPrivateDirectory(transactionsRoot)
    try RecoveryTransactionPathContract.validateExistingPrivateDirectory(candidateDirectory)
    let transactionDirectory = try RecoveryTransactionPathContract.validate(
      candidate: candidateDirectory,
      transactionsRoot: transactionsRoot
    )
    let store = try TransactionStore(directoryURL: transactionDirectory)
    guard let record = try store.load() else {
      throw SafetyError.missingTransaction
    }

    let activeAuthenticationURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("auth.json")
    let recoverySnapshotURL = transactionDirectory.appendingPathComponent("recovery-auth.json")
    let installer = try SecureAuthenticationFileInstaller(
      activeAuthenticationURL: activeAuthenticationURL,
      recoverySnapshotURL: recoverySnapshotURL
    )
    let adapter = try RealChatGPTDesktopAdapter(
      sourceIdentity: record.sourceIdentity,
      profiles: [
        DesktopCredentialProfile(
          identity: record.sourceIdentity,
          authenticationFileURL: recoverySnapshotURL
        )
      ],
      processController: MacOSChatGPTProcessController(),
      identityReader: PinnedAuthenticationIdentityReader(
        authenticationFileURL: activeAuthenticationURL
      ),
      authenticationInstaller: installer
    )

    try RecoveryReadinessMarker.create(
      at: transactionDirectory.appendingPathComponent("recovery.ready")
    )
    _ = try SwitchTransactionEngine(store: store, desktop: adapter)
      .recover(lockBehavior: .waitForActiveTransaction)
  }
}
