import Foundation

public struct CodexAppServerQuotaReader: QuotaReading, ReadOnlyAccountProbing, Sendable {
  public let codexBinaryURL: URL
  public let timeout: Duration

  public init(
    codexBinaryURL: URL = URL(
      fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
    timeout: Duration = .seconds(20)
  ) {
    self.codexBinaryURL = codexBinaryURL
    self.timeout = timeout
  }

  public func fetchSnapshots(for accounts: [AccountRecord]) async throws
    -> [AccountID: AccountQuotaSnapshot]
  {
    let realAccounts = accounts.compactMap { account -> (AccountID, String)? in
      guard case .codexHome(let path) = account.source else { return nil }
      return (account.id, path)
    }

    guard !realAccounts.isEmpty else {
      return [:]
    }

    return try await withThrowingTaskGroup(of: (AccountID, AccountQuotaSnapshot).self) { group in
      for (accountID, path) in realAccounts {
        group.addTask {
          let snapshot = try await Self.readSnapshot(
            from: path,
            binaryURL: codexBinaryURL,
            timeout: timeout
          )
          guard let account = accounts.first(where: { $0.id == accountID }),
            let expectedIdentityHash = account.identityHash
          else {
            throw QuotaReadingError.identityNotPinned
          }
          guard snapshot.identityHash == expectedIdentityHash else {
            throw QuotaReadingError.identityMismatch
          }
          return (
            accountID,
            AccountQuotaSnapshot(
              email: snapshot.email,
              planName: snapshot.planName,
              usage: snapshot.usage
            )
          )
        }
      }

      var result: [AccountID: AccountQuotaSnapshot] = [:]
      for try await (accountID, snapshot) in group {
        result[accountID] = snapshot
      }
      return result
    }
  }

  public func probe(codexHomePath: String) async throws -> ReadOnlyAccountProbe {
    let snapshot = try await Self.readSnapshot(
      from: codexHomePath,
      binaryURL: codexBinaryURL,
      timeout: timeout
    )
    return ReadOnlyAccountProbe(
      identityHash: snapshot.identityHash,
      email: snapshot.email,
      planName: snapshot.planName,
      usage: snapshot.usage
    )
  }

  private static func readSnapshot(from path: String, binaryURL: URL, timeout: Duration)
    async throws -> ReadOnlyQuotaSnapshot
  {
    let stagedHome = try ReadOnlyCodexHomeStage(sourcePath: path)
    defer { stagedHome.remove() }

    return try await Task.detached(priority: .utility) {
      let client = CodexAppServerClient(
        binaryURL: binaryURL,
        codexHome: stagedHome.url,
        timeout: timeout
      )
      return try client.readSnapshot()
    }.value
  }
}

private struct ReadOnlyQuotaSnapshot: Sendable {
  let identityHash: String
  let email: String
  let planName: String
  let usage: AccountUsage
}

public struct MixedQuotaReader: QuotaReading, Sendable {
  private let mockReader: MockQuotaReader
  private let codexReader: CodexAppServerQuotaReader

  public init(codexReader: CodexAppServerQuotaReader = CodexAppServerQuotaReader()) {
    self.mockReader = MockQuotaReader()
    self.codexReader = codexReader
  }

  public func fetchSnapshots(for accounts: [AccountRecord]) async throws
    -> [AccountID: AccountQuotaSnapshot]
  {
    let mockAccounts = accounts.filter {
      if case .mock = $0.source { return true }
      return false
    }
    let realAccounts = accounts.filter {
      if case .codexHome = $0.source { return true }
      return false
    }

    var result = try await mockReader.fetchSnapshots(for: mockAccounts)
    if !realAccounts.isEmpty {
      result.merge(try await codexReader.fetchSnapshots(for: realAccounts)) { _, latest in latest }
    }
    return result
  }
}

private struct ReadOnlyCodexHomeStage: Sendable {
  let url: URL

  init(sourcePath: String) throws {
    let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
    let fileManager = FileManager.default
    let sourceValues = try sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard sourceValues.isSymbolicLink != true else {
      throw QuotaReadingError.invalidHomePath
    }
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw QuotaReadingError.invalidHomePath
    }

    let homeAttributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
    let homePermissions = (homeAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    guard homePermissions & 0o077 == 0 else {
      throw QuotaReadingError.insecureHomePermissions
    }

    let authURL = sourceURL.appendingPathComponent("auth.json")
    guard fileManager.fileExists(atPath: authURL.path) else {
      throw QuotaReadingError.missingAuthenticationFile
    }
    let authValues = try authURL.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard authValues.isSymbolicLink != true else {
      throw QuotaReadingError.invalidAuthenticationFile
    }
    let authAttributes = try fileManager.attributesOfItem(atPath: authURL.path)
    guard authAttributes[.type] as? FileAttributeType == .typeRegular else {
      throw QuotaReadingError.invalidAuthenticationFile
    }
    let authPermissions = (authAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    guard authPermissions == 0o600 else {
      throw QuotaReadingError.insecureHomePermissions
    }

    let stagedURL = fileManager.temporaryDirectory
      .appendingPathComponent("switchgpt-readonly-" + UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(
      at: stagedURL,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )

    do {
      let stagedAuthURL = stagedURL.appendingPathComponent("auth.json")
      try fileManager.copyItem(at: authURL, to: stagedAuthURL)
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagedAuthURL.path)
      self.url = stagedURL
    } catch {
      try? fileManager.removeItem(at: stagedURL)
      throw QuotaReadingError.invalidAuthenticationFile
    }
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}

private struct CodexAppServerClient: Sendable {
  let binaryURL: URL
  let codexHome: URL
  let timeout: Duration

  func readSnapshot() throws -> ReadOnlyQuotaSnapshot {
    guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
      throw QuotaReadingError.missingCodexBinary
    }

    let process = Process()
    process.executableURL = binaryURL
    process.arguments = ["app-server", "--stdio"]

    var environment = ProcessInfo.processInfo.environment
    environment["CODEX_HOME"] = codexHome.path
    environment.removeValue(forKey: "OPENAI_API_KEY")
    environment.removeValue(forKey: "CODEX_API_KEY")
    process.environment = environment

    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = Pipe()

    do {
      try process.run()
    } catch {
      throw QuotaReadingError.processLaunchFailed
    }

    let timeoutItem = DispatchWorkItem {
      if process.isRunning {
        process.terminate()
      }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + timeout.timeInterval,
      execute: timeoutItem
    )

    defer {
      timeoutItem.cancel()
      if process.isRunning {
        process.terminate()
      }
      process.waitUntilExit()
    }

    var nextID = 1
    _ = try request(
      method: "initialize",
      params: [
        "clientInfo": [
          "name": "switchgpt-read-only",
          "title": "SwitchGPT read-only quota reader",
          "version": "0.1.0",
        ],
        "capabilities": NSNull(),
      ],
      input: input,
      output: output,
      nextID: &nextID
    )
    try sendNotification(method: "initialized", input: input)
    let accountData = try request(
      method: "account/read",
      params: ["refreshToken": false],
      input: input,
      output: output,
      nextID: &nextID
    )
    let rateLimitsData = try request(
      method: "account/rateLimits/read",
      params: NSNull(),
      input: input,
      output: output,
      nextID: &nextID
    )
    let accountMetadata = try CodexAccountDecoder.decode(from: accountData)
    return ReadOnlyQuotaSnapshot(
      identityHash: accountMetadata.identityHash,
      email: accountMetadata.email,
      planName: accountMetadata.planName,
      usage: try CodexRateLimitDecoder.decodeUsage(from: rateLimitsData)
    )
  }

  private func sendNotification(method: String, input: Pipe) throws {
    let encoded = try JSONSerialization.data(withJSONObject: ["method": method])
    input.fileHandleForWriting.write(encoded)
    input.fileHandleForWriting.write(Data([0x0A]))
  }

  private func request(
    method: String,
    params: Any,
    input: Pipe,
    output: Pipe,
    nextID: inout Int
  ) throws -> Data {
    let requestID = nextID
    nextID += 1
    let message: [String: Any] = ["id": requestID, "method": method, "params": params]
    let encoded = try JSONSerialization.data(withJSONObject: message)
    input.fileHandleForWriting.write(encoded)
    input.fileHandleForWriting.write(Data([0x0A]))

    var buffer = Data()
    while true {
      // `readData(ofLength:)` can wait for the full requested byte count on a pipe. App-server
      // responses are normally much smaller, so that behavior deadlocks until our timeout kills
      // the child. `availableData` returns as soon as a response chunk is available.
      let chunk = output.fileHandleForReading.availableData
      if chunk.isEmpty {
        throw QuotaReadingError.timedOut
      }
      buffer.append(chunk)

      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = buffer.prefix(upTo: newline)
        buffer.removeSubrange(...newline)
        guard !line.isEmpty else { continue }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
          let response = object as? [String: Any],
          let responseID = response["id"] as? NSNumber,
          responseID.intValue == requestID
        else {
          continue
        }

        if response["error"] != nil {
          throw QuotaReadingError.invalidProtocolResponse
        }
        guard let result = response["result"] else {
          throw QuotaReadingError.invalidProtocolResponse
        }
        return try JSONSerialization.data(withJSONObject: result)
      }
    }
  }
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    let components = self.components
    return TimeInterval(components.seconds) + TimeInterval(components.attoseconds)
      / 1_000_000_000_000_000_000
  }
}
