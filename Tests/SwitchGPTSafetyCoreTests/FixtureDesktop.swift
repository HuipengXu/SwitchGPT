import Darwin
import Foundation

@testable import SwitchGPTSafetyCore

final class FixtureDesktop: TransactionDesktop {
  struct State: Codable {
    var installedIdentity: IdentityID
    var isRunning: Bool
    var startsByIdentity: [String: Int]
    var stopCount: Int
  }

  private let stateURL: URL

  init(directoryURL: URL, initialIdentity: IdentityID? = nil) throws {
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    stateURL = directoryURL.appendingPathComponent("desktop.json")

    if let initialIdentity, !FileManager.default.fileExists(atPath: stateURL.path) {
      try write(
        State(
          installedIdentity: initialIdentity,
          isRunning: true,
          startsByIdentity: [:],
          stopCount: 0
        )
      )
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

  func snapshot() throws -> State {
    try read()
  }

  private func read() throws -> State {
    try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
  }

  private func write(_ state: State) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: stateURL, options: .atomic)
    _ = stateURL.path.withCString { chmod($0, 0o600) }
  }
}
