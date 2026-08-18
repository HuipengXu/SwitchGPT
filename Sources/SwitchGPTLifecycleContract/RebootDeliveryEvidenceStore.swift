import Darwin
import Foundation

public enum RebootDeliveryEvidenceError: Error, Equatable, Sendable {
  case invalidBootSessionIdentifier
  case unsafeStorage
}

public struct BootSessionIdentifier: RawRepresentable, Codable, Equatable, Sendable {
  public let rawValue: String

  public init?(rawValue: String) {
    let components = rawValue.split(separator: "-", omittingEmptySubsequences: false)
    guard
      components.count == 2,
      components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
      components.allSatisfy({ UInt64($0) != nil }),
      rawValue.count <= 64
    else {
      return nil
    }
    self.rawValue = rawValue
  }
}

public enum SystemBootSessionIdentifier {
  public static func current() throws -> BootSessionIdentifier {
    var bootTime = timeval()
    var size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard
      bootTime.tv_sec >= 0,
      bootTime.tv_usec >= 0,
      let identifier = BootSessionIdentifier(
        rawValue: "\(bootTime.tv_sec)-\(bootTime.tv_usec)"
      )
    else {
      throw RebootDeliveryEvidenceError.invalidBootSessionIdentifier
    }
    return identifier
  }
}

public enum RebootDeliveryEvidenceStatus: String, Codable, Equatable, Sendable {
  case notArmed
  case armedOnCurrentBoot
  case rebootOccurredWithoutDelivery
  case deliveredOnCurrentBoot
  case deliveredOnPriorBoot
  case duplicateDeliveryDetected
}

public enum RebootDeliveryRecordingOutcome: String, Codable, Equatable, Sendable {
  case inactive
  case armedForFutureBoot
  case rebootDeliveryRecorded
  case duplicateDeliveryDetected
}

/// Durable, metadata-only evidence for Phase C. It stores only boot-session identifiers.
/// Arming, first delivery, and duplicate detection are all write-once operations.
public final class RebootDeliveryEvidenceStore {
  private static let directoryName = "reboot-delivery"
  private static let armedFileName = "armed-boot.identifier"
  private static let deliveredFileName = "delivered-boot.identifier"
  private static let duplicateFileName = "duplicate-delivery.detected"

  public let directoryURL: URL
  private let armedURL: URL
  private let deliveredURL: URL
  private let duplicateURL: URL

  public init(sessionURL: URL) throws {
    directoryURL = sessionURL.appendingPathComponent(Self.directoryName, isDirectory: true)
    armedURL = directoryURL.appendingPathComponent(Self.armedFileName)
    deliveredURL = directoryURL.appendingPathComponent(Self.deliveredFileName)
    duplicateURL = directoryURL.appendingPathComponent(Self.duplicateFileName)
    do {
      try SecureActivationAttemptStorage.requirePrivateDirectory(sessionURL)
      try SecureActivationAttemptStorage.preparePrivateDirectory(directoryURL)
    } catch {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
  }

  private init(existingSessionURL sessionURL: URL) throws {
    directoryURL = sessionURL.appendingPathComponent(Self.directoryName, isDirectory: true)
    armedURL = directoryURL.appendingPathComponent(Self.armedFileName)
    deliveredURL = directoryURL.appendingPathComponent(Self.deliveredFileName)
    duplicateURL = directoryURL.appendingPathComponent(Self.duplicateFileName)
    do {
      try SecureActivationAttemptStorage.requirePrivateDirectory(sessionURL)
      try SecureActivationAttemptStorage.requirePrivateDirectory(directoryURL)
    } catch {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
  }

  public static func openExisting(sessionURL: URL) throws -> RebootDeliveryEvidenceStore? {
    let directoryURL = sessionURL.appendingPathComponent(directoryName, isDirectory: true)
    do {
      guard try SecureActivationAttemptStorage.privateDirectoryExists(directoryURL) else {
        return nil
      }
      return try RebootDeliveryEvidenceStore(existingSessionURL: sessionURL)
    } catch {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
  }

  @discardableResult
  public func arm(on bootSession: BootSessionIdentifier) throws -> Bool {
    do {
      let created = try SecureActivationAttemptStorage.writeExclusivePrivateFile(
        encoded(bootSession),
        to: armedURL,
        in: directoryURL
      )
      if !created, try readIdentifier(at: armedURL) != bootSession {
        throw RebootDeliveryEvidenceError.unsafeStorage
      }
      return created
    } catch let error as RebootDeliveryEvidenceError {
      throw error
    } catch {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
  }

  public func status(
    on bootSession: BootSessionIdentifier
  ) throws -> RebootDeliveryEvidenceStatus {
    do {
      guard let armed = try readIdentifierIfPresent(at: armedURL) else {
        return .notArmed
      }
      let delivered = try readIdentifierIfPresent(at: deliveredURL)
      let duplicate = try readDuplicateMarker()
      if duplicate { return .duplicateDeliveryDetected }
      guard let delivered else {
        return armed == bootSession ? .armedOnCurrentBoot : .rebootOccurredWithoutDelivery
      }
      guard delivered != armed else {
        throw RebootDeliveryEvidenceError.unsafeStorage
      }
      return delivered == bootSession ? .deliveredOnCurrentBoot : .deliveredOnPriorBoot
    } catch let error as RebootDeliveryEvidenceError {
      throw error
    } catch {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
  }

  public func recordDelivery(
    on bootSession: BootSessionIdentifier
  ) throws -> RebootDeliveryRecordingOutcome {
    do {
      guard let armed = try readIdentifierIfPresent(at: armedURL) else {
        return .inactive
      }
      if armed == bootSession { return .armedForFutureBoot }

      let created = try SecureActivationAttemptStorage.writeExclusivePrivateFile(
        encoded(bootSession),
        to: deliveredURL,
        in: directoryURL
      )
      if created { return .rebootDeliveryRecorded }

      guard try readIdentifier(at: deliveredURL) == bootSession else {
        throw RebootDeliveryEvidenceError.unsafeStorage
      }
      _ = try SecureActivationAttemptStorage.writeExclusivePrivateFile(
        Data("duplicate\n".utf8),
        to: duplicateURL,
        in: directoryURL
      )
      guard try readDuplicateMarker() else {
        throw RebootDeliveryEvidenceError.unsafeStorage
      }
      return .duplicateDeliveryDetected
    } catch let error as RebootDeliveryEvidenceError {
      throw error
    } catch {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
  }

  private func encoded(_ identifier: BootSessionIdentifier) -> Data {
    Data("v1:\(identifier.rawValue)\n".utf8)
  }

  private func readIdentifier(at url: URL) throws -> BootSessionIdentifier {
    guard let identifier = try readIdentifierIfPresent(at: url) else {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
    return identifier
  }

  private func readIdentifierIfPresent(at url: URL) throws -> BootSessionIdentifier? {
    guard
      let data = try SecureActivationAttemptStorage.readPrivateFileIfPresent(
        at: url,
        in: directoryURL
      )
    else {
      return nil
    }
    guard
      let value = String(data: data, encoding: .utf8),
      value.hasPrefix("v1:"),
      value.hasSuffix("\n"),
      value.filter({ $0 == "\n" }).count == 1,
      let identifier = BootSessionIdentifier(
        rawValue: String(value.dropFirst(3).dropLast())
      )
    else {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
    return identifier
  }

  private func readDuplicateMarker() throws -> Bool {
    guard
      let data = try SecureActivationAttemptStorage.readPrivateFileIfPresent(
        at: duplicateURL,
        in: directoryURL
      )
    else {
      return false
    }
    guard data == Data("duplicate\n".utf8) else {
      throw RebootDeliveryEvidenceError.unsafeStorage
    }
    return true
  }
}
