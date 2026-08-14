import Foundation
import SwitchGPTLifecycleContract
@_spi(SafetyTesting) import SwitchGPTSafetyCore

struct MatrixReport: Codable {
  let totalScenarios: Int
  let passedScenarios: Int
  let abruptExitScenarios: Int
  let crossProcessActivationBudgetVerified: Bool
  let crossProcessLockVerified: Bool
}

struct ChildResult {
  let status: Int32
  let standardOutput: Data
  let standardError: Data
}

final class MatrixRunner {
  private let executableURL: URL
  private let bootRecoveryExecutableURL: URL
  private let fileManager = FileManager.default
  private let accountA = IdentityID(rawValue: "account-a")!
  private let accountB = IdentityID(rawValue: "account-b")!

  init(executableURL: URL) {
    self.executableURL = executableURL
    bootRecoveryExecutableURL = executableURL.deletingLastPathComponent()
      .appendingPathComponent("SwitchGPTBootRecovery")
  }

  func run() throws -> MatrixReport {
    let matrixRoot = fileManager.temporaryDirectory
      .appendingPathComponent("switchgpt-safety-matrix-\(UUID().uuidString)")
    try fileManager.createDirectory(at: matrixRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: matrixRoot) }

    var passed = 0
    var abruptExits = 0

    try runSuccessfulSwitch(in: scenario("success", under: matrixRoot))
    passed += 1

    try runVerificationRollback(in: scenario("verification-rollback", under: matrixRoot))
    passed += 1

    let forwardCheckpoints: [SafetyCheckpoint] = [
      .afterPrepared,
      .afterTargetStopped,
      .afterTargetInstalled,
      .afterTargetLaunchReserved,
      .afterTargetStarted,
    ]
    for checkpoint in forwardCheckpoints {
      try runForwardCrash(checkpoint, in: scenario(checkpoint.rawValue, under: matrixRoot))
      passed += 1
      abruptExits += 1
    }

    let rollbackCheckpoints: [SafetyCheckpoint] = [
      .afterRollbackStopped,
      .afterSourceRestored,
      .afterRollbackLaunchReserved,
      .afterRollbackStarted,
    ]
    for checkpoint in rollbackCheckpoints {
      try runRollbackCrash(checkpoint, in: scenario(checkpoint.rawValue, under: matrixRoot))
      passed += 1
      abruptExits += 1
    }

    let durableWriteCheckpoints: [DurableWriteCheckpoint] = [
      .afterTemporaryFileSynchronized,
      .afterDirectorySynchronized,
    ]
    for checkpoint in durableWriteCheckpoints {
      try runDurableWriteCrash(
        checkpoint,
        in: scenario(checkpoint.rawValue, under: matrixRoot)
      )
      passed += 1
      abruptExits += 1
    }

    try runSupervisorNormalExit(in: scenario("supervisor-normal", under: matrixRoot))
    passed += 1

    try runSupervisorCrash(
      helperCount: 1,
      checkpoint: .afterTargetInstalled,
      in: scenario("supervisor-crash", under: matrixRoot)
    )
    passed += 1
    abruptExits += 1

    try runSupervisorCrash(
      helperCount: 2,
      checkpoint: .afterTargetStarted,
      in: scenario("duplicate-supervisor-crash", under: matrixRoot)
    )
    passed += 1
    abruptExits += 1

    try runRepeatedBootRecovery(in: scenario("repeated-boot-recovery", under: matrixRoot))
    passed += 1
    abruptExits += 1

    try runRepeatedBootManualRecovery(
      in: scenario("repeated-boot-manual-recovery", under: matrixRoot)
    )
    passed += 1
    abruptExits += 1

    try runRepeatedBootAfterCommit(in: scenario("repeated-boot-after-commit", under: matrixRoot))
    passed += 1

    try runBootEntrySafety(in: scenario("boot-entry-safety", under: matrixRoot))
    passed += 1

    try runBootEntryCorruptedState(in: scenario("boot-entry-corrupt", under: matrixRoot))
    passed += 1
    abruptExits += 1

    try runBootEntrySymlinkEscape(
      in: scenario("boot-entry-symlink", under: matrixRoot),
      target: scenario("boot-entry-symlink-target", under: matrixRoot)
    )
    passed += 1

    try runConcurrentBootRecovery(in: scenario("concurrent-boot-recovery", under: matrixRoot))
    passed += 1
    abruptExits += 1

    try runCrossProcessLock(in: scenario("cross-process-lock", under: matrixRoot))
    passed += 1

    try runConcurrentActivationReservation(
      .registration,
      in: scenario("concurrent-registration-reservation", under: matrixRoot)
    )
    passed += 1

    try runConcurrentActivationReservation(
      .unregistration,
      in: scenario("concurrent-unregistration-reservation", under: matrixRoot)
    )
    passed += 1

    return MatrixReport(
      totalScenarios: 26,
      passedScenarios: passed,
      abruptExitScenarios: abruptExits,
      crossProcessActivationBudgetVerified: true,
      crossProcessLockVerified: true
    )
  }

  private func runDurableWriteCrash(_ checkpoint: DurableWriteCheckpoint, in root: URL) throws {
    try seed(root)
    let crashed = try runChild([
      "worker-begin-durable-crash", root.path, checkpoint.rawValue, "5",
    ])
    try require(crashed.status == SimulatorCLI.abruptExitStatus, "durable write crash exit")
    try expectSuccess(runChild(["worker-recover", root.path]), command: "durable write recovery")

    let snapshot = try inspect(root)
    try require(snapshot.phase == .rolledBack, "durable write recovery phase")
    try require(snapshot.mode == .recoveryOnly, "durable write recovery mode")
    try require(snapshot.installedIdentity == accountA, "durable write recovery identity")
    try require(snapshot.rollbackLaunchAttempts == 1, "durable write rollback budget")
    try require(snapshot.startsByIdentity[accountB.rawValue, default: 0] == 0, "no target start")
    try require(snapshot.startsByIdentity[accountA.rawValue] == 1, "single source start")

    let expectedTargetBudget = checkpoint == .afterDirectorySynchronized ? 1 : 0
    try require(
      snapshot.targetLaunchAttempts == expectedTargetBudget,
      "durable write target budget"
    )
  }

  private func runSupervisorNormalExit(in root: URL) throws {
    try seed(root)
    try expectSuccess(
      runChild(["worker-supervised-begin", root.path, "none", "match", "1"]),
      command: "supervised begin"
    )
    try waitForSupervisorCompletion(root: root, helperCount: 1)

    let snapshot = try inspect(root)
    try require(snapshot.phase == .committed, "supervisor normal phase")
    try require(snapshot.installedIdentity == accountB, "supervisor normal identity")
    try require(snapshot.startsByIdentity[accountB.rawValue] == 1, "supervisor target start")
    try require(snapshot.startsByIdentity[accountA.rawValue, default: 0] == 0, "no rollback")
  }

  private func runSupervisorCrash(
    helperCount: Int,
    checkpoint: SafetyCheckpoint,
    in root: URL
  ) throws {
    try seed(root)
    let crashed = try runChild([
      "worker-supervised-begin", root.path, checkpoint.rawValue, "match", String(helperCount),
    ])
    try require(crashed.status == SimulatorCLI.abruptExitStatus, "supervised crash exit")
    try waitForSupervisorCompletion(root: root, helperCount: helperCount)

    let snapshot = try inspect(root)
    try require(snapshot.phase == .rolledBack, "supervised crash phase")
    try require(snapshot.mode == .recoveryOnly, "supervised crash mode")
    try require(snapshot.installedIdentity == accountA, "supervised crash identity")
    try require(snapshot.rollbackLaunchAttempts == 1, "supervised rollback budget")
    let expectedTargetStarts = checkpoint == .afterTargetStarted ? 1 : 0
    try require(
      snapshot.startsByIdentity[accountB.rawValue, default: 0] == expectedTargetStarts,
      "supervised target starts"
    )
    try require(snapshot.startsByIdentity[accountA.rawValue] == 1, "single supervised rollback")
  }

  private func waitForSupervisorCompletion(root: URL, helperCount: Int) throws {
    let doneURLs = (0..<helperCount).map {
      root.appendingPathComponent("supervisor-done-\($0)")
    }
    let deadline = Date().addingTimeInterval(5)
    while !doneURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }), Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    try require(
      doneURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }),
      "supervisor completion"
    )
  }

  private func runRepeatedBootRecovery(in root: URL) throws {
    try seed(root)
    let crashed = try runChild([
      "worker-begin", root.path, SafetyCheckpoint.afterTargetStarted.rawValue, "match",
    ])
    try require(crashed.status == SimulatorCLI.abruptExitStatus, "boot recovery crash exit")
    try runBootEntryTwice(root, first: .recovered, second: .terminal)

    let snapshot = try inspect(root)
    try require(snapshot.phase == .rolledBack, "boot recovery phase")
    try require(snapshot.installedIdentity == accountA, "boot recovery identity")
    try require(snapshot.startsByIdentity[accountB.rawValue] == 1, "boot target start")
    try require(snapshot.startsByIdentity[accountA.rawValue] == 1, "single boot rollback")
  }

  private func runRepeatedBootManualRecovery(in root: URL) throws {
    try seed(root)
    let crashed = try runChild([
      "worker-begin", root.path, SafetyCheckpoint.afterRollbackLaunchReserved.rawValue,
      "mismatch",
    ])
    try require(crashed.status == SimulatorCLI.abruptExitStatus, "boot manual crash exit")
    try runBootEntryTwice(
      root,
      first: .manualRecoveryRequired,
      second: .manualRecoveryRequired
    )

    let snapshot = try inspect(root)
    try require(snapshot.phase == .manualRecoveryRequired, "boot manual phase")
    try require(snapshot.installedIdentity == accountA, "boot manual identity")
    try require(!snapshot.isRunning, "boot manual stopped")
    try require(snapshot.startsByIdentity[accountA.rawValue, default: 0] == 0, "boot no retry")
  }

  private func runRepeatedBootAfterCommit(in root: URL) throws {
    try seed(root)
    try expectSuccess(runChild(["worker-begin", root.path, "none", "match"]), command: "commit")
    try runBootEntryTwice(root, first: .terminal, second: .terminal)

    let snapshot = try inspect(root)
    try require(snapshot.phase == .committed, "boot committed phase")
    try require(snapshot.installedIdentity == accountB, "boot committed identity")
    try require(snapshot.startsByIdentity[accountB.rawValue] == 1, "boot committed start")
    try require(snapshot.startsByIdentity[accountA.rawValue, default: 0] == 0, "boot no rollback")
  }

  private func runBootEntryTwice(
    _ root: URL,
    first firstOutcome: BootRecoveryOutcome,
    second secondOutcome: BootRecoveryOutcome
  ) throws {
    let first = try runBootRecovery(root: root, arguments: [BootRecoveryEntry.command])
    try expectBootOutcome(first, expected: firstOutcome, command: "first boot entry")
    let second = try runBootRecovery(root: root, arguments: [BootRecoveryEntry.command])
    try expectBootOutcome(second, expected: secondOutcome, command: "second boot entry")
  }

  private func runBootEntrySafety(in root: URL) throws {
    try seed(root)

    let invalid = try runBootRecovery(root: root, arguments: ["begin-switch"])
    try expectBootOutcome(invalid, expected: .invalidInvocation, command: "invalid boot entry")

    let missingArgument = try runBootRecovery(root: root, arguments: [])
    try expectBootOutcome(
      missingArgument,
      expected: .invalidInvocation,
      command: "missing boot command"
    )

    let inactiveRoot = root.appendingPathComponent("inactive-fixture", isDirectory: true)
    try seed(inactiveRoot)
    let inactive = try runBootRecovery(
      root: inactiveRoot,
      arguments: [BootRecoveryEntry.command]
    )
    try expectBootOutcome(inactive, expected: .inactive, command: "inactive boot entry")

    let unsafe = try runBootRecovery(
      root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
      arguments: [BootRecoveryEntry.command]
    )
    try expectBootOutcome(unsafe, expected: .unsafeState, command: "unsafe boot root")

    let desktop = try SimulatorDesktop(directoryURL: root.appendingPathComponent("desktop"))
      .snapshot()
    try require(desktop.installedIdentity == accountA, "boot safety identity")
    try require(desktop.isRunning, "boot safety running")
    try require(desktop.stopCount == 0, "boot safety stop count")
    try require(desktop.startsByIdentity.isEmpty, "boot safety starts")
  }

  private func runBootEntryCorruptedState(in root: URL) throws {
    try seed(root)
    let crashed = try runChild([
      "worker-begin", root.path, SafetyCheckpoint.afterPrepared.rawValue, "match",
    ])
    try require(crashed.status == SimulatorCLI.abruptExitStatus, "corrupt boot setup exit")

    let stateURL = root.appendingPathComponent("transaction/transaction.json")
    try Data("{".utf8).write(to: stateURL, options: .atomic)
    try require(stateURL.path.withCString { chmod($0, 0o600) } == 0, "corrupt state mode")

    let corrupted = try runBootRecovery(root: root, arguments: [BootRecoveryEntry.command])
    try expectBootOutcome(corrupted, expected: .unsafeState, command: "corrupt boot entry")

    let desktop = try SimulatorDesktop(directoryURL: root.appendingPathComponent("desktop"))
      .snapshot()
    try require(desktop.installedIdentity == accountA, "corrupt boot identity")
    try require(desktop.isRunning, "corrupt boot running")
    try require(desktop.stopCount == 0, "corrupt boot stops")
    try require(desktop.startsByIdentity.isEmpty, "corrupt boot starts")
  }

  private func runBootEntrySymlinkEscape(in root: URL, target: URL) throws {
    try seed(root)
    let targetDesktop = try SimulatorDesktop(
      directoryURL: target.appendingPathComponent("desktop"),
      initialIdentity: accountA
    )
    let desktopURL = root.appendingPathComponent("desktop")
    try fileManager.removeItem(at: desktopURL)
    try fileManager.createSymbolicLink(
      at: desktopURL,
      withDestinationURL: target.appendingPathComponent("desktop")
    )

    let escaped = try runBootRecovery(root: root, arguments: [BootRecoveryEntry.command])
    try expectBootOutcome(escaped, expected: .unsafeState, command: "symlink boot entry")

    let state = try targetDesktop.snapshot()
    try require(state.installedIdentity == accountA, "symlink target identity")
    try require(state.isRunning, "symlink target running")
    try require(state.stopCount == 0, "symlink target stops")
    try require(state.startsByIdentity.isEmpty, "symlink target starts")
  }

  private func runConcurrentBootRecovery(in root: URL) throws {
    try seed(root)
    let crashed = try runChild([
      "worker-begin", root.path, SafetyCheckpoint.afterTargetStarted.rawValue, "match",
    ])
    try require(crashed.status == SimulatorCLI.abruptExitStatus, "concurrent boot setup exit")

    let environment = bootEnvironment(root: root)
    let children = try (0..<2).map { _ in
      try startProcess(
        executableURL: bootRecoveryExecutableURL,
        arguments: [BootRecoveryEntry.command],
        environment: environment
      )
    }
    let results = children.map { finishProcess($0) }
    try require(results.allSatisfy { $0.status == 0 }, "concurrent boot exit")
    let outcomes = results.map {
      String(decoding: $0.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    try require(outcomes.contains(BootRecoveryOutcome.recovered.rawValue), "one boot recovery")
    try require(
      outcomes.allSatisfy {
        [
          BootRecoveryOutcome.recovered.rawValue,
          BootRecoveryOutcome.terminal.rawValue,
          BootRecoveryOutcome.unsafeState.rawValue,
        ].contains($0)
      },
      "concurrent boot outcomes"
    )

    let snapshot = try inspect(root)
    try require(snapshot.phase == .rolledBack, "concurrent boot phase")
    try require(snapshot.installedIdentity == accountA, "concurrent boot identity")
    try require(snapshot.startsByIdentity[accountA.rawValue] == 1, "concurrent single rollback")
  }

  private func runBootRecovery(root: URL, arguments: [String]) throws -> ChildResult {
    let environment = bootEnvironment(root: root)
    return try runProcess(
      executableURL: bootRecoveryExecutableURL,
      arguments: arguments,
      environment: environment
    )
  }

  private func bootEnvironment(root: URL) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["SWITCHGPT_SAFETY_ROOT"] = root.path
    return environment
  }

  private func expectBootOutcome(
    _ result: ChildResult,
    expected: BootRecoveryOutcome?,
    command: String
  ) throws {
    try expectSuccess(result, command: command)
    if let expected {
      let output = String(decoding: result.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      try require(output == expected.rawValue, "\(command) outcome")
    }
  }

  private func runSuccessfulSwitch(in root: URL) throws {
    try seed(root)
    try expectSuccess(runChild(["worker-begin", root.path, "none", "match"]), command: "begin")
    let snapshot = try inspect(root)
    try require(snapshot.phase == .committed, "success phase")
    try require(snapshot.installedIdentity == accountB, "success identity")
    try require(snapshot.targetLaunchAttempts == 1, "success target budget")
    try require(snapshot.rollbackLaunchAttempts == 0, "success rollback budget")
  }

  private func runVerificationRollback(in root: URL) throws {
    try seed(root)
    try expectSuccess(
      runChild(["worker-begin", root.path, "none", "mismatch"]),
      command: "verification rollback"
    )
    let snapshot = try inspect(root)
    try require(snapshot.phase == .rolledBack, "verification rollback phase")
    try require(snapshot.installedIdentity == accountA, "verification rollback identity")
    try require(snapshot.startsByIdentity[accountB.rawValue] == 1, "target start count")
    try require(snapshot.startsByIdentity[accountA.rawValue] == 1, "rollback start count")
  }

  private func runForwardCrash(_ checkpoint: SafetyCheckpoint, in root: URL) throws {
    try seed(root)
    let crashed = try runChild([
      "worker-begin", root.path, checkpoint.rawValue, "match",
    ])
    try require(crashed.status == SimulatorCLI.abruptExitStatus, "forward crash exit")
    try expectSuccess(runChild(["worker-recover", root.path]), command: "forward recovery")

    let snapshot = try inspect(root)
    try require(snapshot.phase == .rolledBack, "forward recovery phase")
    try require(snapshot.mode == .recoveryOnly, "forward recovery mode")
    try require(snapshot.installedIdentity == accountA, "forward recovery identity")
    try require(snapshot.rollbackLaunchAttempts == 1, "forward rollback budget")
    let expectedTargetStarts = checkpoint == .afterTargetStarted ? 1 : 0
    try require(
      snapshot.startsByIdentity[accountB.rawValue, default: 0] == expectedTargetStarts,
      "forward target start count"
    )
    try require(snapshot.startsByIdentity[accountA.rawValue] == 1, "forward source start count")
  }

  private func runRollbackCrash(_ checkpoint: SafetyCheckpoint, in root: URL) throws {
    try seed(root)
    let crashed = try runChild([
      "worker-begin", root.path, checkpoint.rawValue, "mismatch",
    ])
    try require(crashed.status == SimulatorCLI.abruptExitStatus, "rollback crash exit")
    try expectSuccess(runChild(["worker-recover", root.path]), command: "rollback recovery")

    let snapshot = try inspect(root)
    try require(snapshot.mode == .recoveryOnly, "rollback recovery mode")
    try require(snapshot.installedIdentity == accountA, "rollback recovery identity")
    try require(snapshot.targetLaunchAttempts == 1, "rollback target budget")
    try require(snapshot.rollbackLaunchAttempts == 1, "rollback launch budget")
    try require(snapshot.startsByIdentity[accountB.rawValue] == 1, "rollback target starts")

    if checkpoint == .afterRollbackLaunchReserved {
      try require(snapshot.phase == .manualRecoveryRequired, "manual recovery phase")
      try require(!snapshot.isRunning, "manual recovery stopped")
      try require(snapshot.startsByIdentity[accountA.rawValue, default: 0] == 0, "no retry")
    } else {
      try require(snapshot.phase == .rolledBack, "rollback recovery phase")
      try require(snapshot.isRunning, "rollback source running")
      try require(snapshot.startsByIdentity[accountA.rawValue] == 1, "single source start")
    }
  }

  private func runCrossProcessLock(in root: URL) throws {
    try seed(root)
    let holder = Process()
    holder.executableURL = executableURL
    holder.arguments = ["worker-hold-lock", root.path]
    holder.standardOutput = Pipe()
    holder.standardError = Pipe()
    try holder.run()
    defer {
      if holder.isRunning { holder.terminate() }
      holder.waitUntilExit()
    }

    let readyURL = root.appendingPathComponent("lock-ready")
    let deadline = Date().addingTimeInterval(3)
    while !fileManager.fileExists(atPath: readyURL.path), Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    try require(fileManager.fileExists(atPath: readyURL.path), "lock holder readiness")

    let rejected = try runChild(["worker-begin", root.path, "none", "match"])
    try require(rejected.status == SimulatorCLI.lockUnavailableStatus, "cross-process lock")
  }

  private func runConcurrentActivationReservation(
    _ operation: LifecycleActivationOperation,
    in root: URL
  ) throws {
    try SimulatorSandbox(path: root.path).createRoot()
    let children = try (0..<2).map { _ in
      try startProcess(
        executableURL: executableURL,
        arguments: ["worker-reserve-activation", root.path, operation.rawValue],
        environment: nil
      )
    }
    let results = children.map { finishProcess($0) }
    try require(results.allSatisfy { $0.status == 0 }, "activation reservation exits")

    let outcomes = results.map {
      String(decoding: $0.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    try require(outcomes.filter { $0 == "reserved" }.count == 1, "single reservation winner")
    try require(
      outcomes.filter { $0 == "alreadyReserved" }.count == 1,
      "single reservation loser"
    )

    let later = try runChild([
      "worker-reserve-activation", root.path, operation.rawValue,
    ])
    try expectSuccess(later, command: "later activation reservation")
    let laterOutcome = String(decoding: later.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try require(laterOutcome == "alreadyReserved", "reservation survives process replacement")
  }

  private func seed(_ root: URL) throws {
    try expectSuccess(runChild(["worker-seed", root.path]), command: "seed")
  }

  private func inspect(_ root: URL) throws -> SimulatorSnapshot {
    let result = try runChild(["worker-inspect", root.path])
    try expectSuccess(result, command: "inspect")
    return try JSONDecoder().decode(SimulatorSnapshot.self, from: result.standardOutput)
  }

  private func runChild(_ arguments: [String]) throws -> ChildResult {
    try runProcess(
      executableURL: executableURL,
      arguments: arguments,
      environment: nil
    )
  }

  private func runProcess(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]?
  ) throws -> ChildResult {
    finishProcess(
      try startProcess(
        executableURL: executableURL,
        arguments: arguments,
        environment: environment
      )
    )
  }

  private func startProcess(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]?
  ) throws -> (process: Process, output: Pipe, error: Pipe) {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = output
    process.standardError = error
    try process.run()
    return (process, output, error)
  }

  private func finishProcess(
    _ child: (process: Process, output: Pipe, error: Pipe)
  ) -> ChildResult {
    child.process.waitUntilExit()
    return ChildResult(
      status: child.process.terminationStatus,
      standardOutput: child.output.fileHandleForReading.readDataToEndOfFile(),
      standardError: child.error.fileHandleForReading.readDataToEndOfFile()
    )
  }

  private func expectSuccess(_ result: ChildResult, command: String) throws {
    guard result.status == 0 else {
      throw SimulatorError.childFailed(command: command, status: result.status)
    }
  }

  private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw SimulatorError.assertionFailed(message) }
  }

  private func scenario(_ name: String, under root: URL) -> URL {
    root.appendingPathComponent(name, isDirectory: true)
  }
}
