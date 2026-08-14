import Darwin
import Foundation

enum SecureFileIO {
  static let privateDirectoryMode: mode_t = 0o700
  static let privateFileMode: mode_t = 0o600

  static func preparePrivateDirectory(at url: URL) throws {
    let fileManager = FileManager.default
    var created = false
    if try statusIfPresent(at: url) == nil {
      try fileManager.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: privateDirectoryMode]
      )
      try changeMode(privateDirectoryMode, at: url)
      created = true
    }
    try validatePrivateDirectory(at: url)
    if created {
      try synchronizeDirectory(at: url.deletingLastPathComponent())
    }
  }

  static func validatePrivateDirectory(at url: URL) throws {
    guard
      let status = try statusIfPresent(at: url),
      isDirectory(status),
      status.st_uid == geteuid(),
      permissionBits(status) == privateDirectoryMode
    else {
      throw SafetyError.unsafeStorage
    }
  }

  static func validatePrivateRegularFile(at url: URL) throws {
    guard
      let status = try statusIfPresent(at: url),
      isRegularFile(status),
      status.st_uid == geteuid(),
      status.st_nlink == 1,
      permissionBits(status) == privateFileMode
    else {
      throw SafetyError.unsafeStorage
    }
  }

  static func statusIfPresent(at url: URL) throws -> stat? {
    var status = stat()
    let result = url.path.withCString { lstat($0, &status) }
    if result == 0 { return status }
    if errno == ENOENT { return nil }
    throw currentPOSIXError()
  }

  static func validateOpenPrivateRegularFile(_ descriptor: Int32) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else { throw currentPOSIXError() }
    guard
      isRegularFile(status),
      status.st_uid == geteuid(),
      status.st_nlink == 1,
      permissionBits(status) == privateFileMode
    else {
      throw SafetyError.unsafeStorage
    }
  }

  static func changeMode(_ mode: mode_t, at url: URL) throws {
    guard url.path.withCString({ chmod($0, mode) }) == 0 else {
      throw currentPOSIXError()
    }
  }

  static func synchronizeFile(_ descriptor: Int32) throws {
    if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
    guard fsync(descriptor) == 0 else { throw currentPOSIXError() }
  }

  static func synchronizeDirectory(at url: URL) throws {
    let descriptor = url.path.withCString {
      open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else { throw currentPOSIXError() }
    defer { close(descriptor) }

    guard fsync(descriptor) == 0 else { throw currentPOSIXError() }
  }

  static func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  private static func isDirectory(_ status: stat) -> Bool {
    status.st_mode & S_IFMT == S_IFDIR
  }

  private static func isRegularFile(_ status: stat) -> Bool {
    status.st_mode & S_IFMT == S_IFREG
  }

  private static func permissionBits(_ status: stat) -> mode_t {
    status.st_mode & 0o777
  }
}
