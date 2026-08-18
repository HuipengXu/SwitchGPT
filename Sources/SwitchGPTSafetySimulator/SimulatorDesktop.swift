import Darwin
import Foundation
import SwitchGPTSafetyCore

struct SimulatorDesktopState: Codable, Equatable {
  var installedIdentity: IdentityID
  var isRunning: Bool
  var startsByIdentity: [String: Int]
  var stopCount: Int
}

final class SimulatorDesktop: TransactionDesktop {
  private let directoryURL: URL
  private let stateURL: URL

  init(directoryURL: URL, initialIdentity: IdentityID? = nil) throws {
    self.directoryURL = directoryURL
    stateURL = directoryURL.appendingPathComponent("desktop.json")

    if let initialIdentity {
      guard !FileManager.default.fileExists(atPath: stateURL.path) else {
        throw SimulatorError.fixtureAlreadyExists
      }
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try setMode(0o700, at: directoryURL)
      try write(
        SimulatorDesktopState(
          installedIdentity: initialIdentity,
          isRunning: true,
          startsByIdentity: [:],
          stopCount: 0
        )
      )
    } else {
      guard FileManager.default.fileExists(atPath: stateURL.path) else {
        throw SimulatorError.fixtureMissing
      }
    }
  }

  func isRunning() throws -> Bool {
    try read().isRunning
  }

  func currentIdentity() throws -> IdentityID {
    try read().installedIdentity
  }

  func stop() throws {
    var state = try read()
    state.isRunning = false
    state.stopCount += 1
    try write(state)
  }

  func install(identity: IdentityID) throws {
    var state = try read()
    state.installedIdentity = identity
    try write(state)
  }

  func start() throws {
    var state = try read()
    state.isRunning = true
    state.startsByIdentity[state.installedIdentity.rawValue, default: 0] += 1
    try write(state)
  }

  func snapshot() throws -> SimulatorDesktopState {
    try read()
  }

  private func read() throws -> SimulatorDesktopState {
    try JSONDecoder().decode(
      SimulatorDesktopState.self,
      from: Data(contentsOf: stateURL)
    )
  }

  private func write(_ state: SimulatorDesktopState) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: stateURL, options: .atomic)
    try setMode(0o600, at: stateURL)
  }

  private func setMode(_ mode: mode_t, at url: URL) throws {
    let result = url.path.withCString { chmod($0, mode) }
    guard result == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}

struct SimulatorSnapshot: Codable {
  let phase: TransactionPhase
  let mode: TransactionMode
  let targetLaunchAttempts: Int
  let rollbackLaunchAttempts: Int
  let installedIdentity: IdentityID
  let isRunning: Bool
  let startsByIdentity: [String: Int]
  let stopCount: Int

  init(record: TransactionRecord, desktop: SimulatorDesktopState) {
    phase = record.phase
    mode = record.mode
    targetLaunchAttempts = record.targetLaunchAttempts
    rollbackLaunchAttempts = record.rollbackLaunchAttempts
    installedIdentity = desktop.installedIdentity
    isRunning = desktop.isRunning
    startsByIdentity = desktop.startsByIdentity
    stopCount = desktop.stopCount
  }
}
