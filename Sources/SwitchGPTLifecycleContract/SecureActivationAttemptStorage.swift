import Darwin
import Foundation

enum SecureActivationAttemptStorageError: Error {
  case unsafeStorage
}

/// File-level primitive shared by fixture and real validation ledgers.
/// Its root must already be a private directory owned by the current user.
final class SecureActivationAttemptStorage {
  static let directoryMode: mode_t = 0o700
  static let fileMode: mode_t = 0o600

  let rootURL: URL
  let directoryURL: URL

  convenience init(rootURL: URL) throws {
    try self.init(rootURL: rootURL, createDirectory: true)
  }

  convenience init(existingRootURL rootURL: URL) throws {
    try self.init(rootURL: rootURL, createDirectory: false)
  }

  private init(rootURL: URL, createDirectory: Bool) throws {
    self.rootURL = rootURL.standardizedFileURL
    directoryURL = self.rootURL.appendingPathComponent(
      "activation-attempts",
      isDirectory: true
    )
    try Self.requirePrivateDirectory(self.rootURL)
    if createDirectory {
      try Self.preparePrivateDirectory(directoryURL)
    } else {
      try Self.requirePrivateDirectory(directoryURL)
    }
  }

  func reserve(_ operation: LifecycleActivationOperation) throws -> Bool {
    try Self.requirePrivateDirectory(rootURL)
    try Self.requirePrivateDirectory(directoryURL)
    let reservationURL = directoryURL.appendingPathComponent(
      "\(operation.rawValue).reserved"
    )

    let descriptor = reservationURL.path.withCString {
      open(
        $0,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
        Self.fileMode
      )
    }
    if descriptor < 0, errno == EEXIST {
      try Self.requirePrivateRegularFile(reservationURL)
      return false
    }
    guard descriptor >= 0 else { throw Self.currentPOSIXError() }
    defer { close(descriptor) }

    guard fchmod(descriptor, Self.fileMode) == 0 else {
      throw Self.currentPOSIXError()
    }
    try Self.requireOpenPrivateRegularFile(descriptor)
    let marker = Array("reserved\n".utf8)
    try marker.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var writtenCount = 0
      while writtenCount < bytes.count {
        let written = write(
          descriptor,
          baseAddress.advanced(by: writtenCount),
          bytes.count - writtenCount
        )
        if written < 0 {
          if errno == EINTR { continue }
          throw Self.currentPOSIXError()
        }
        writtenCount += written
      }
    }
    try Self.synchronizeFile(descriptor)
    try Self.synchronizeDirectory(directoryURL)
    return true
  }

  func hasReservation(_ operation: LifecycleActivationOperation) throws -> Bool {
    try Self.requirePrivateDirectory(rootURL)
    try Self.requirePrivateDirectory(directoryURL)
    let reservationURL = directoryURL.appendingPathComponent(
      "\(operation.rawValue).reserved"
    )
    let descriptor = reservationURL.path.withCString {
      open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    if descriptor < 0, errno == ENOENT { return false }
    guard descriptor >= 0 else { throw Self.currentPOSIXError() }
    defer { close(descriptor) }

    try Self.requireOpenPrivateRegularFile(descriptor)
    var bytes = [UInt8](repeating: 0, count: 10)
    let count = read(descriptor, &bytes, bytes.count)
    guard count >= 0 else { throw Self.currentPOSIXError() }
    guard count == 9, Array(bytes.prefix(count)) == Array("reserved\n".utf8) else {
      throw SecureActivationAttemptStorageError.unsafeStorage
    }
    return true
  }

  static func preparePrivateDirectory(_ url: URL) throws {
    let standardizedURL = url.standardizedFileURL
    let result = standardizedURL.path.withCString { mkdir($0, directoryMode) }
    if result == 0 {
      guard standardizedURL.path.withCString({ chmod($0, directoryMode) }) == 0 else {
        throw currentPOSIXError()
      }
      try requirePrivateDirectory(standardizedURL)
      try synchronizeDirectory(standardizedURL.deletingLastPathComponent())
      return
    }
    guard errno == EEXIST else { throw currentPOSIXError() }
    try requirePrivateDirectory(standardizedURL)
  }

  static func requirePrivateDirectory(_ url: URL) throws {
    let status = try fileStatus(at: url)
    guard
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == geteuid(),
      status.st_mode & 0o777 == directoryMode
    else {
      throw SecureActivationAttemptStorageError.unsafeStorage
    }
  }

  static func privateDirectoryExists(_ url: URL) throws -> Bool {
    do {
      try requirePrivateDirectory(url)
      return true
    } catch let error as POSIXError where error.code == .ENOENT {
      return false
    }
  }

  static func writeExclusivePrivateFile(
    _ data: Data,
    to url: URL,
    in directoryURL: URL
  ) throws -> Bool {
    guard
      url.deletingLastPathComponent().standardizedFileURL
        == directoryURL.standardizedFileURL,
      !data.isEmpty,
      data.count <= 256
    else {
      throw SecureActivationAttemptStorageError.unsafeStorage
    }
    try requirePrivateDirectory(directoryURL)

    let descriptor = url.path.withCString {
      open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, fileMode)
    }
    if descriptor < 0, errno == EEXIST {
      try requirePrivateRegularFile(url)
      return false
    }
    guard descriptor >= 0 else { throw currentPOSIXError() }
    defer { close(descriptor) }

    guard fchmod(descriptor, fileMode) == 0 else { throw currentPOSIXError() }
    try requireOpenPrivateRegularFile(descriptor)
    try data.withUnsafeBytes { bytes in
      guard var address = bytes.baseAddress else { return }
      var remaining = bytes.count
      while remaining > 0 {
        let written = write(descriptor, address, remaining)
        if written < 0 {
          if errno == EINTR { continue }
          throw currentPOSIXError()
        }
        remaining -= written
        address = address.advanced(by: written)
      }
    }
    try synchronizeFile(descriptor)
    try synchronizeDirectory(directoryURL)
    return true
  }

  static func readPrivateFileIfPresent(
    at url: URL,
    in directoryURL: URL,
    maximumBytes: Int = 256
  ) throws -> Data? {
    guard
      url.deletingLastPathComponent().standardizedFileURL
        == directoryURL.standardizedFileURL,
      maximumBytes > 0,
      maximumBytes <= 4096
    else {
      throw SecureActivationAttemptStorageError.unsafeStorage
    }
    try requirePrivateDirectory(directoryURL)
    let descriptor = url.path.withCString {
      open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    if descriptor < 0, errno == ENOENT { return nil }
    guard descriptor >= 0 else { throw currentPOSIXError() }
    defer { close(descriptor) }
    try requireOpenPrivateRegularFile(descriptor)

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 128)
    while true {
      let count = read(descriptor, &buffer, buffer.count)
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        throw currentPOSIXError()
      }
      guard result.count + count <= maximumBytes else {
        throw SecureActivationAttemptStorageError.unsafeStorage
      }
      result.append(buffer, count: count)
    }
    return result
  }

  static func requirePrivateRegularFile(_ url: URL) throws {
    let status = try fileStatus(at: url)
    guard
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_nlink == 1,
      status.st_mode & 0o777 == fileMode
    else {
      throw SecureActivationAttemptStorageError.unsafeStorage
    }
  }

  static func requireOpenPrivateRegularFile(_ descriptor: Int32) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else { throw currentPOSIXError() }
    guard
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_nlink == 1,
      status.st_mode & 0o777 == fileMode
    else {
      throw SecureActivationAttemptStorageError.unsafeStorage
    }
  }

  private static func fileStatus(at url: URL) throws -> stat {
    var status = stat()
    guard url.path.withCString({ lstat($0, &status) }) == 0 else {
      throw currentPOSIXError()
    }
    return status
  }

  static func synchronizeFile(_ descriptor: Int32) throws {
    if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
    guard fsync(descriptor) == 0 else { throw currentPOSIXError() }
  }

  static func synchronizeDirectory(_ url: URL) throws {
    let descriptor = url.path.withCString {
      open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else { throw currentPOSIXError() }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else { throw currentPOSIXError() }
  }

  private static func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
