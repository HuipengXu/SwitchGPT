import Darwin
import Foundation
import SwitchGPTLifecycleContract
@_spi(SafetyTesting) import SwitchGPTSafetyCore

@main
enum SimulatorCLI {
  static let abruptExitStatus: Int32 = 97
  static let lockUnavailableStatus: Int32 = 75

  private static let accountA = IdentityID(rawValue: "account-a")!
  private static let accountB = IdentityID(rawValue: "account-b")!

  static func main() {
    do {
      try run(Array(CommandLine.arguments.dropFirst()))
      exit(0)
    } catch SafetyError.lockUnavailable {
      writeError("lock_unavailable")
      exit(lockUnavailableStatus)
    } catch SimulatorError.unsafeRoot {
      writeError("unsafe_root")
      exit(64)
    } catch SimulatorError.usage {
      writeError("usage: SwitchGPTSafetySimulator matrix")
      exit(64)
    } catch let SimulatorError.childFailed(command, status) {
      writeError("simulation_failed:child_failed:\(command):\(status)")
      exit(1)
    } catch let SimulatorError.assertionFailed(message) {
      writeError("simulation_failed:assertion:\(message)")
      exit(1)
    } catch {
      writeError("simulation_failed")
      exit(1)
    }
  }

  private static func run(_ arguments: [String]) throws {
    guard let command = arguments.first else { throw SimulatorError.usage }
    switch command {
    case "matrix":
      guard arguments.count == 1 else { throw SimulatorError.usage }
      let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
      let report = try MatrixRunner(executableURL: executableURL).run()
      try writeJSON(report)
    case "worker-seed":
      let sandbox = try sandbox(arguments, expectedCount: 2)
      try sandbox.createRoot()
      _ = try SimulatorDesktop(
        directoryURL: sandbox.desktopDirectoryURL,
        initialIdentity: accountA
      )
    case "worker-begin":
      guard arguments.count == 4 else { throw SimulatorError.usage }
      let sandbox = try SimulatorSandbox(path: arguments[1])
      let checkpoint = try parseCheckpoint(arguments[2])
      let forceMismatch = arguments[3] == "mismatch"
      guard forceMismatch || arguments[3] == "match" else { throw SimulatorError.usage }
      let desktop = try SimulatorDesktop(directoryURL: sandbox.desktopDirectoryURL)
      let store = try TransactionStore(directoryURL: sandbox.transactionDirectoryURL)
      let engine = SwitchTransactionEngine(store: store, desktop: desktop) { point in
        if forceMismatch, point == .afterTargetStarted {
          try desktop.install(identity: accountA)
        }
        if point == checkpoint {
          _exit(abruptExitStatus)
        }
      }
      _ = try engine.beginSwitch(from: accountA, to: accountB)
    case "worker-supervised-begin":
      guard arguments.count == 5 else { throw SimulatorError.usage }
      let sandbox = try SimulatorSandbox(path: arguments[1])
      let checkpoint = try parseCheckpoint(arguments[2])
      let forceMismatch = arguments[3] == "mismatch"
      guard forceMismatch || arguments[3] == "match" else { throw SimulatorError.usage }
      guard let helperCount = Int(arguments[4]), (1...2).contains(helperCount) else {
        throw SimulatorError.usage
      }

      let desktop = try SimulatorDesktop(directoryURL: sandbox.desktopDirectoryURL)
      let store = try TransactionStore(directoryURL: sandbox.transactionDirectoryURL)
      var supervisors: [Process] = []
      let recoverySupervisor = ClosureRecoverySupervisor {
        for index in 0..<helperCount {
          let supervisor = Process()
          supervisor.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
          supervisor.arguments = ["worker-supervise", sandbox.rootURL.path, String(index)]
          try supervisor.run()
          supervisors.append(supervisor)
        }
        try waitForFiles(
          (0..<helperCount).map { sandbox.supervisorReadyURL(index: $0) },
          timeout: 3
        )
      }
      let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
      let hostEvidence = SupervisorHostEvidence(
        hostBundleIdentifier: "com.switchgpt.safety-simulator",
        expectedHostBundleIdentifier: "com.switchgpt.safety-simulator",
        targetBundleIdentifier: "com.openai.codex",
        expectedHostTeamIdentifier: "SWITCHGPT-SAFETY-FIXTURE",
        signatureEvidence: .verified(
          teamIdentifier: "SWITCHGPT-SAFETY-FIXTURE",
          signingIdentifier: "com.switchgpt.safety-simulator"
        ),
        executableURL: executableURL,
        expectedHostBundleURL: executableURL.deletingLastPathComponent(),
        targetBundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true),
        ancestorExecutableURLs: [],
        launchMechanism: .application
      )
      let independentSupervisor = IndependentSwitchSupervisor(
        store: store,
        desktop: desktop,
        hostEvidence: hostEvidence,
        recoverySupervisor: recoverySupervisor
      ) { point in
        if forceMismatch, point == .afterTargetStarted {
          try desktop.install(identity: accountA)
        }
        if point == checkpoint {
          _exit(abruptExitStatus)
        }
      }
      _ = try independentSupervisor.beginSwitch(from: accountA, to: accountB)
      for supervisor in supervisors {
        supervisor.waitUntilExit()
        guard supervisor.terminationStatus == 0 else {
          throw SimulatorError.childFailed(
            command: "supervisor",
            status: supervisor.terminationStatus
          )
        }
      }
    case "worker-begin-durable-crash":
      guard arguments.count == 4 else { throw SimulatorError.usage }
      let sandbox = try SimulatorSandbox(path: arguments[1])
      guard let checkpoint = DurableWriteCheckpoint(rawValue: arguments[2]) else {
        throw SimulatorError.invalidCheckpoint
      }
      guard let selectedWrite = Int(arguments[3]), selectedWrite > 0 else {
        throw SimulatorError.usage
      }
      var writeNumber = 0
      let store = try TransactionStore(
        directoryURL: sandbox.transactionDirectoryURL
      ) { point in
        if point == .afterTemporaryFileSynchronized {
          writeNumber += 1
        }
        if point == checkpoint, writeNumber == selectedWrite {
          _exit(abruptExitStatus)
        }
      }
      let desktop = try SimulatorDesktop(directoryURL: sandbox.desktopDirectoryURL)
      _ = try SwitchTransactionEngine(store: store, desktop: desktop)
        .beginSwitch(from: accountA, to: accountB)
    case "worker-supervise":
      guard arguments.count == 3, let index = Int(arguments[2]), index >= 0 else {
        throw SimulatorError.usage
      }
      let sandbox = try SimulatorSandbox(path: arguments[1])
      let desktop = try SimulatorDesktop(directoryURL: sandbox.desktopDirectoryURL)
      let store = try TransactionStore(directoryURL: sandbox.transactionDirectoryURL)
      try writeMarker(at: sandbox.supervisorReadyURL(index: index), sandbox: sandbox)
      _ = try SwitchTransactionEngine(store: store, desktop: desktop)
        .recover(lockBehavior: .waitForActiveTransaction)
      try writeMarker(at: sandbox.supervisorDoneURL(index: index), sandbox: sandbox)
    case "worker-recover":
      let sandbox = try sandbox(arguments, expectedCount: 2)
      let desktop = try SimulatorDesktop(directoryURL: sandbox.desktopDirectoryURL)
      let store = try TransactionStore(directoryURL: sandbox.transactionDirectoryURL)
      _ = try SwitchTransactionEngine(store: store, desktop: desktop).recover()
    case "worker-inspect":
      let sandbox = try sandbox(arguments, expectedCount: 2)
      let desktop = try SimulatorDesktop(directoryURL: sandbox.desktopDirectoryURL)
      let store = try TransactionStore(directoryURL: sandbox.transactionDirectoryURL)
      guard let record = try store.load() else { throw SimulatorError.fixtureMissing }
      try writeJSON(SimulatorSnapshot(record: record, desktop: desktop.snapshot()))
    case "worker-hold-lock":
      let sandbox = try sandbox(arguments, expectedCount: 2)
      let store = try TransactionStore(directoryURL: sandbox.transactionDirectoryURL)
      let lock = try TransactionLock(url: store.lockURL)
      try Data("ready".utf8).write(to: sandbox.lockReadyURL, options: .atomic)
      try sandbox.setMode(0o600, at: sandbox.lockReadyURL)
      Thread.sleep(forTimeInterval: 10)
      lock.release()
    case "worker-reserve-activation":
      guard
        arguments.count == 3,
        let operation = LifecycleActivationOperation(rawValue: arguments[2])
      else {
        throw SimulatorError.usage
      }
      let sandbox = try SimulatorSandbox(path: arguments[1])
      let recorder = try TemporaryActivationAttemptRecorder(rootURL: sandbox.rootURL)
      let outcome = try recorder.reserve(operation) ? "reserved" : "alreadyReserved"
      FileHandle.standardOutput.write(Data("\(outcome)\n".utf8))
    default:
      throw SimulatorError.usage
    }
  }

  private static func sandbox(_ arguments: [String], expectedCount: Int) throws -> SimulatorSandbox
  {
    guard arguments.count == expectedCount else { throw SimulatorError.usage }
    return try SimulatorSandbox(path: arguments[1])
  }

  private static func parseCheckpoint(_ value: String) throws -> SafetyCheckpoint? {
    if value == "none" { return nil }
    guard let checkpoint = SafetyCheckpoint(rawValue: value) else {
      throw SimulatorError.invalidCheckpoint
    }
    return checkpoint
  }

  private static func waitForFiles(_ urls: [URL], timeout: TimeInterval) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
      guard Date() < deadline else {
        throw SimulatorError.fixtureMissing
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
  }

  private static func writeMarker(at url: URL, sandbox: SimulatorSandbox) throws {
    try Data("ready".utf8).write(to: url, options: .atomic)
    try sandbox.setMode(0o600, at: url)
  }

  private static func writeJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(value))
    FileHandle.standardOutput.write(Data([0x0A]))
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }
}

private final class ClosureRecoverySupervisor: OneShotRecoverySupervisor {
  private let armHandler: () throws -> Void

  init(_ armHandler: @escaping () throws -> Void) {
    self.armHandler = armHandler
  }

  func armAndWaitUntilReady() throws {
    try armHandler()
  }
}
