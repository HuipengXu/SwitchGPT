import Darwin
import Foundation

public enum RealSwitchReceiptOutcome: String, Codable, Equatable, Sendable {
  case committed
  case rolledBack
  case manualRecoveryRequired
}

public enum RealSwitchReceiptFailureReason: String, Codable, Equatable, Sendable {
  case targetOperationFailed
  case targetIdentityMismatch
  case interrupted
  case recoveryOperationFailed
  case recoveryLaunchBudgetExhausted
}

/// Metadata-only evidence written after an experimental desktop switch reaches a terminal phase.
/// It intentionally excludes account names, local paths, authentication data, and token claims.
public struct RealSwitchReceipt: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let id: UUID
  public let sourceIdentityHash: String
  public let targetIdentityHash: String
  public let outcome: RealSwitchReceiptOutcome
  public let finalIdentityHash: String?
  public let targetLaunchAttempts: Int
  public let rollbackLaunchAttempts: Int
  public let targetWasInstalled: Bool
  public let failureReason: RealSwitchReceiptFailureReason?
  public let transactionCreatedAt: Date
  public let recordedAt: Date

  public init(
    id: UUID,
    sourceIdentityHash: String,
    targetIdentityHash: String,
    outcome: RealSwitchReceiptOutcome,
    finalIdentityHash: String?,
    targetLaunchAttempts: Int,
    rollbackLaunchAttempts: Int,
    targetWasInstalled: Bool,
    failureReason: RealSwitchReceiptFailureReason?,
    transactionCreatedAt: Date,
    recordedAt: Date = Date()
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.id = id
    self.sourceIdentityHash = sourceIdentityHash
    self.targetIdentityHash = targetIdentityHash
    self.outcome = outcome
    self.finalIdentityHash = finalIdentityHash
    self.targetLaunchAttempts = targetLaunchAttempts
    self.rollbackLaunchAttempts = rollbackLaunchAttempts
    self.targetWasInstalled = targetWasInstalled
    self.failureReason = failureReason
    self.transactionCreatedAt = transactionCreatedAt
    self.recordedAt = recordedAt
  }
}

public enum RealSwitchReceiptStoreError: Error, Equatable, Sendable {
  case invalidReceipt
  case unsafeStorage
  case receiptAlreadyExists
  case invalidReceiptFile
}

/// An append-only private store for terminal switch receipts. Receipt IDs come from the safety
/// transaction, so a completed transaction cannot silently overwrite its prior evidence.
public struct RealSwitchReceiptStore: Sendable {
  public static let maximumFileSize = 64 * 1024

  public let directoryURL: URL

  public static var defaultStore: RealSwitchReceiptStore {
    let applicationSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return RealSwitchReceiptStore(
      directoryURL:
        applicationSupport
        .appendingPathComponent("SwitchGPT", isDirectory: true)
        .appendingPathComponent("SwitchReceipts", isDirectory: true)
    )
  }

  public init(directoryURL: URL) {
    self.directoryURL = directoryURL.standardizedFileURL
  }

  @discardableResult
  public func save(_ receipt: RealSwitchReceipt) throws -> URL {
    try validate(receipt)
    try preparePrivateDirectory()

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(receipt)
    guard data.count <= Self.maximumFileSize else {
      throw RealSwitchReceiptStoreError.invalidReceipt
    }

    let receiptURL = url(for: receipt.id)
    let descriptor = receiptURL.path.withCString {
      open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
    }
    guard descriptor >= 0 else {
      if errno == EEXIST { throw RealSwitchReceiptStoreError.receiptAlreadyExists }
      throw RealSwitchReceiptStoreError.unsafeStorage
    }

    var completed = false
    defer {
      close(descriptor)
      if !completed { unlink(receiptURL.path) }
    }

    guard try validateOpenPrivateFile(descriptor) else {
      throw RealSwitchReceiptStoreError.unsafeStorage
    }
    try data.withUnsafeBytes { bytes in
      guard var address = bytes.baseAddress else { return }
      var remaining = bytes.count
      while remaining > 0 {
        let count = Darwin.write(descriptor, address, remaining)
        if count < 0 {
          if errno == EINTR { continue }
          throw RealSwitchReceiptStoreError.unsafeStorage
        }
        address = address.advanced(by: count)
        remaining -= count
      }
    }
    guard fsync(descriptor) == 0 else {
      throw RealSwitchReceiptStoreError.unsafeStorage
    }
    try synchronizeDirectory()
    completed = true
    return receiptURL
  }

  public func load(id: UUID) throws -> RealSwitchReceipt? {
    let receiptURL = url(for: id)
    let descriptor = receiptURL.path.withCString { open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
    guard descriptor >= 0 else {
      if errno == ENOENT { return nil }
      throw RealSwitchReceiptStoreError.invalidReceiptFile
    }
    defer { close(descriptor) }
    guard try validateOpenPrivateFile(descriptor) else {
      throw RealSwitchReceiptStoreError.invalidReceiptFile
    }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        throw RealSwitchReceiptStoreError.invalidReceiptFile
      }
      guard data.count + count <= Self.maximumFileSize else {
        throw RealSwitchReceiptStoreError.invalidReceiptFile
      }
      data.append(buffer, count: count)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let receipt = try? decoder.decode(RealSwitchReceipt.self, from: data) else {
      throw RealSwitchReceiptStoreError.invalidReceiptFile
    }
    try validate(receipt)
    return receipt
  }

  private func url(for id: UUID) -> URL {
    directoryURL.appendingPathComponent(id.uuidString.lowercased() + ".json")
  }

  private func validate(_ receipt: RealSwitchReceipt) throws {
    guard receipt.schemaVersion == RealSwitchReceipt.currentSchemaVersion,
      isIdentityHash(receipt.sourceIdentityHash),
      isIdentityHash(receipt.targetIdentityHash),
      receipt.sourceIdentityHash != receipt.targetIdentityHash,
      receipt.finalIdentityHash.map(isIdentityHash) ?? true,
      (0...1).contains(receipt.targetLaunchAttempts),
      (0...1).contains(receipt.rollbackLaunchAttempts),
      receipt.recordedAt >= receipt.transactionCreatedAt
    else {
      throw RealSwitchReceiptStoreError.invalidReceipt
    }
  }

  private func isIdentityHash(_ value: String) -> Bool {
    value.count == 12 && value.allSatisfy(\.isHexDigit)
  }

  private func preparePrivateDirectory() throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: directoryURL.path) {
      let values = try directoryURL.resourceValues(forKeys: [.isSymbolicLinkKey])
      let attributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
      guard values.isSymbolicLink != true,
        attributes[.type] as? FileAttributeType == .typeDirectory,
        (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
      else {
        throw RealSwitchReceiptStoreError.unsafeStorage
      }
      return
    }

    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try fileManager.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directoryURL.path
      )
    } catch {
      throw RealSwitchReceiptStoreError.unsafeStorage
    }
  }

  private func validateOpenPrivateFile(_ descriptor: Int32) throws -> Bool {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw RealSwitchReceiptStoreError.unsafeStorage
    }
    return status.st_mode & S_IFMT == S_IFREG
      && status.st_uid == geteuid()
      && status.st_nlink == 1
      && status.st_mode & 0o777 == 0o600
  }

  private func synchronizeDirectory() throws {
    let descriptor = directoryURL.path.withCString {
      open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else { throw RealSwitchReceiptStoreError.unsafeStorage }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else { throw RealSwitchReceiptStoreError.unsafeStorage }
  }
}
