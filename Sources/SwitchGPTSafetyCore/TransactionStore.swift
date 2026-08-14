import CryptoKit
import Darwin
import Foundation

public final class TransactionStore {
  static let maximumStateBytes = 1_048_576

  public let directoryURL: URL
  public var stateURL: URL { directoryURL.appendingPathComponent("transaction.json") }
  public var lockURL: URL { directoryURL.appendingPathComponent("transaction.lock") }

  private let envelopeEncoder: JSONEncoder
  private let recordEncoder: JSONEncoder
  private let decoder: JSONDecoder
  private let writeCheckpointHandler: (DurableWriteCheckpoint) throws -> Void

  public convenience init(directoryURL: URL) throws {
    try self.init(
      directoryURL: directoryURL,
      testingWriteCheckpointHandler: { _ in }
    )
  }

  @_spi(SafetyTesting)
  public convenience init(
    directoryURL: URL,
    writeCheckpointHandler: @escaping (DurableWriteCheckpoint) throws -> Void
  ) throws {
    try self.init(
      directoryURL: directoryURL,
      testingWriteCheckpointHandler: writeCheckpointHandler
    )
  }

  init(
    directoryURL: URL,
    testingWriteCheckpointHandler: @escaping (DurableWriteCheckpoint) throws -> Void
  ) throws {
    self.directoryURL = directoryURL
    writeCheckpointHandler = testingWriteCheckpointHandler

    envelopeEncoder = JSONEncoder()
    envelopeEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    envelopeEncoder.dateEncodingStrategy = .secondsSince1970

    recordEncoder = JSONEncoder()
    recordEncoder.outputFormatting = [.sortedKeys]
    recordEncoder.dateEncodingStrategy = .secondsSince1970

    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    try SecureFileIO.preparePrivateDirectory(at: directoryURL)
  }

  public func load() throws -> TransactionRecord? {
    try SecureFileIO.validatePrivateDirectory(at: directoryURL)
    guard try SecureFileIO.statusIfPresent(at: stateURL) != nil else { return nil }
    try SecureFileIO.validatePrivateRegularFile(at: stateURL)

    let data = try readStateFile()
    let envelope: PersistedEnvelope
    do {
      envelope = try decoder.decode(PersistedEnvelope.self, from: data)
    } catch {
      throw SafetyError.corruptedPersistedState
    }
    guard envelope.envelopeSchemaVersion == PersistedEnvelope.currentSchemaVersion else {
      throw SafetyError.unsupportedEnvelopeSchemaVersion(envelope.envelopeSchemaVersion)
    }
    guard envelope.checksum == (try checksum(for: envelope.record)) else {
      throw SafetyError.corruptedPersistedState
    }
    let record = envelope.record
    try validate(record)
    return record
  }

  public func save(_ record: TransactionRecord) throws {
    try SecureFileIO.validatePrivateDirectory(at: directoryURL)
    try validate(record)
    if try SecureFileIO.statusIfPresent(at: stateURL) != nil {
      try SecureFileIO.validatePrivateRegularFile(at: stateURL)
    }

    let envelope = PersistedEnvelope(record: record, checksum: try checksum(for: record))
    let data = try envelopeEncoder.encode(envelope)
    try durableAtomicWrite(data)
  }

  private func readStateFile() throws -> Data {
    let descriptor = stateURL.path.withCString {
      open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      if errno == ELOOP { throw SafetyError.unsafeStorage }
      throw SecureFileIO.currentPOSIXError()
    }
    defer { close(descriptor) }
    try SecureFileIO.validateOpenPrivateRegularFile(descriptor)

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = read(descriptor, &buffer, buffer.count)
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        throw SecureFileIO.currentPOSIXError()
      }
      guard result.count + count <= Self.maximumStateBytes else {
        throw SafetyError.corruptedPersistedState
      }
      result.append(buffer, count: count)
    }
    return result
  }

  private func durableAtomicWrite(_ data: Data) throws {
    let temporaryURL = directoryURL.appendingPathComponent(
      ".transaction-\(UUID().uuidString).tmp"
    )
    var descriptor = temporaryURL.path.withCString {
      open(
        $0,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
        SecureFileIO.privateFileMode
      )
    }
    guard descriptor >= 0 else { throw SecureFileIO.currentPOSIXError() }

    var renamed = false
    defer {
      if descriptor >= 0 { close(descriptor) }
      if !renamed { try? FileManager.default.removeItem(at: temporaryURL) }
    }

    try SecureFileIO.validateOpenPrivateRegularFile(descriptor)
    try data.withUnsafeBytes { rawBuffer in
      guard var baseAddress = rawBuffer.baseAddress else { return }
      var remaining = rawBuffer.count
      while remaining > 0 {
        let written = write(descriptor, baseAddress, remaining)
        if written < 0 {
          if errno == EINTR { continue }
          throw SecureFileIO.currentPOSIXError()
        }
        remaining -= written
        baseAddress = baseAddress.advanced(by: written)
      }
    }
    try SecureFileIO.synchronizeFile(descriptor)
    try writeCheckpointHandler(.afterTemporaryFileSynchronized)
    guard close(descriptor) == 0 else {
      descriptor = -1
      throw SecureFileIO.currentPOSIXError()
    }
    descriptor = -1

    guard
      temporaryURL.path.withCString({ source in
        stateURL.path.withCString { destination in rename(source, destination) }
      }) == 0
    else {
      throw SecureFileIO.currentPOSIXError()
    }
    renamed = true
    try SecureFileIO.synchronizeDirectory(at: directoryURL)
    try writeCheckpointHandler(.afterDirectorySynchronized)
  }

  private func checksum(for record: TransactionRecord) throws -> String {
    let digest = SHA256.hash(data: try recordEncoder.encode(record))
    let digits = Array("0123456789abcdef".utf8)
    var result = [UInt8]()
    result.reserveCapacity(SHA256.byteCount * 2)
    for byte in digest {
      result.append(digits[Int(byte >> 4)])
      result.append(digits[Int(byte & 0x0F)])
    }
    return String(decoding: result, as: UTF8.self)
  }

  private func validate(_ record: TransactionRecord) throws {
    guard record.schemaVersion == TransactionRecord.currentSchemaVersion else {
      throw SafetyError.unsupportedSchemaVersion(record.schemaVersion)
    }
    guard
      record.sourceIdentity != record.targetIdentity,
      record.recoveryIdentity == record.sourceIdentity,
      (0...1).contains(record.targetLaunchAttempts),
      (0...1).contains(record.rollbackLaunchAttempts)
    else {
      throw SafetyError.invalidPersistedState
    }
  }
}

@_spi(SafetyTesting)
public enum DurableWriteCheckpoint: String, Sendable {
  case afterTemporaryFileSynchronized
  case afterDirectorySynchronized
}

private struct PersistedEnvelope: Codable {
  static let currentSchemaVersion = 1

  let envelopeSchemaVersion: Int
  let record: TransactionRecord
  let checksum: String

  init(record: TransactionRecord, checksum: String) {
    envelopeSchemaVersion = Self.currentSchemaVersion
    self.record = record
    self.checksum = checksum
  }
}
