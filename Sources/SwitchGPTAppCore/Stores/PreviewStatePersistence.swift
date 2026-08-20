import Foundation

public struct PreviewState: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let accounts: [AccountRecord]
  public let currentAccountID: AccountID?
  public let lastRefreshedAt: Date?

  public init(
    accounts: [AccountRecord],
    currentAccountID: AccountID?,
    lastRefreshedAt: Date? = nil,
    schemaVersion: Int = PreviewState.currentSchemaVersion
  ) {
    self.schemaVersion = schemaVersion
    self.accounts = accounts
    self.currentAccountID = currentAccountID
    self.lastRefreshedAt = lastRefreshedAt
  }
}

public enum PreviewStatePersistenceError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedSchema
  case emptyAccounts
  case invalidAccount
  case duplicateAccountID
  case invalidCurrentAccount
  case unsupportedAccountSource
  case invalidFile
  case insecureFile
  case oversizedFile
  case invalidDirectory

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchema:
      return "The saved preview state uses an unsupported schema."
    case .emptyAccounts:
      return "The saved preview state contains no accounts."
    case .invalidAccount:
      return "The saved preview state contains an invalid account."
    case .duplicateAccountID:
      return "The saved preview state contains duplicate account IDs."
    case .invalidCurrentAccount:
      return "The saved preview state has no valid current account."
    case .unsupportedAccountSource:
      return "The saved preview state contains an unsupported account source."
    case .invalidFile:
      return "The saved preview state is not a regular file."
    case .insecureFile:
      return "The saved preview state has insecure file permissions."
    case .oversizedFile:
      return "The saved preview state is unexpectedly large."
    case .invalidDirectory:
      return "The preview state directory is invalid or insecure."
    }
  }
}

public protocol PreviewStatePersisting: Sendable {
  func load() throws -> PreviewState?
  func save(_ state: PreviewState) throws
  func remove() throws
}

/// The default used by AppCore tests and callers that explicitly want session-only state.
public struct NoopPreviewStateStore: PreviewStatePersisting, Sendable {
  public init() {}

  public func load() throws -> PreviewState? { nil }

  public func save(_ state: PreviewState) throws {}

  public func remove() throws {}
}

/// Stores account display metadata, pinned identity hashes, and configured local paths in the
/// app's private Application Support directory. Authentication contents are never persisted here.
public struct PreviewStateFileStore: PreviewStatePersisting, Sendable {
  public static let maximumFileSize = 1 * 1024 * 1024

  public let fileURL: URL

  public static var defaultStore: PreviewStateFileStore {
    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory
    return PreviewStateFileStore(
      fileURL:
        applicationSupport
        .appendingPathComponent("SwitchGPT", isDirectory: true)
        .appendingPathComponent("preview-state.json")
    )
  }

  public init(fileURL: URL) {
    self.fileURL = fileURL.standardizedFileURL
  }

  public func load() throws -> PreviewState? {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }

    try validateRegularFile(at: fileURL, fileManager: fileManager)
    let data = try Data(contentsOf: fileURL)
    guard data.count <= Self.maximumFileSize else {
      throw PreviewStatePersistenceError.oversizedFile
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let state: PreviewState
    do {
      state = try decoder.decode(PreviewState.self, from: data)
    } catch {
      throw PreviewStatePersistenceError.invalidFile
    }
    try validate(state)
    return state
  }

  public func save(_ state: PreviewState) throws {
    try validate(state)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(state)
    guard data.count <= Self.maximumFileSize else {
      throw PreviewStatePersistenceError.oversizedFile
    }

    let fileManager = FileManager.default
    let directoryURL = fileURL.deletingLastPathComponent()
    try prepareDirectory(at: directoryURL, fileManager: fileManager)

    let temporaryURL = directoryURL.appendingPathComponent(
      "." + fileURL.lastPathComponent + "." + UUID().uuidString + ".tmp"
    )
    do {
      try data.write(to: temporaryURL, options: .withoutOverwriting)
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)

      if fileManager.fileExists(atPath: fileURL.path) {
        _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
      } else {
        try fileManager.moveItem(at: temporaryURL, to: fileURL)
      }
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    } catch {
      try? fileManager.removeItem(at: temporaryURL)
      if let typedError = error as? PreviewStatePersistenceError {
        throw typedError
      }
      throw PreviewStatePersistenceError.invalidFile
    }
  }

  public func remove() throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    try validateRegularFile(at: fileURL, fileManager: fileManager)
    try fileManager.removeItem(at: fileURL)
  }

  private func validate(_ state: PreviewState) throws {
    guard state.schemaVersion == PreviewState.currentSchemaVersion else {
      throw PreviewStatePersistenceError.unsupportedSchema
    }
    guard !state.accounts.isEmpty else {
      throw PreviewStatePersistenceError.emptyAccounts
    }

    var identifiers = Set<AccountID>()
    for account in state.accounts {
      guard !account.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !account.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw PreviewStatePersistenceError.invalidAccount
      }
      if let email = account.email {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 320,
          normalized.contains("@"),
          !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
          throw PreviewStatePersistenceError.invalidAccount
        }
      }
      guard identifiers.insert(account.id).inserted else {
        throw PreviewStatePersistenceError.duplicateAccountID
      }
      switch account.source {
      case .mock:
        guard account.identityHash == nil else {
          throw PreviewStatePersistenceError.unsupportedAccountSource
        }
      case .codexHome(let path):
        guard path.hasPrefix("/"), isValidIdentityHash(account.identityHash) else {
          throw PreviewStatePersistenceError.unsupportedAccountSource
        }
      }
    }

    if let currentAccountID = state.currentAccountID {
      guard state.accounts.contains(where: { $0.id == currentAccountID }) else {
        throw PreviewStatePersistenceError.invalidCurrentAccount
      }
    }
  }

  private func isValidIdentityHash(_ value: String?) -> Bool {
    guard let value, value.count == 12 else { return false }
    return value.allSatisfy { $0.isHexDigit }
  }

  private func prepareDirectory(at url: URL, fileManager: FileManager) throws {
    if fileManager.fileExists(atPath: url.path) {
      let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
      guard values.isSymbolicLink != true else {
        throw PreviewStatePersistenceError.invalidDirectory
      }
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        throw PreviewStatePersistenceError.invalidDirectory
      }
      let attributes = try fileManager.attributesOfItem(atPath: url.path)
      let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
      guard permissions & 0o077 == 0 else {
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return
      }
      return
    }

    try fileManager.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }

  private func validateRegularFile(at url: URL, fileManager: FileManager) throws {
    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard values.isSymbolicLink != true else {
      throw PreviewStatePersistenceError.invalidFile
    }
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw PreviewStatePersistenceError.invalidFile
    }
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    guard permissions == 0o600 else {
      throw PreviewStatePersistenceError.insecureFile
    }
  }
}
