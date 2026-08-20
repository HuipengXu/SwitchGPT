import Darwin
import Foundation

public final class SecureAuthenticationFileInstaller: AuthenticationStateInstalling {
  public static let maximumAuthenticationBytes = 4 * 1024 * 1024

  public let activeAuthenticationURL: URL
  public let recoverySnapshotURL: URL

  public init(activeAuthenticationURL: URL, recoverySnapshotURL: URL) throws {
    self.activeAuthenticationURL = activeAuthenticationURL.standardizedFileURL
    self.recoverySnapshotURL = recoverySnapshotURL.standardizedFileURL
    try Self.preparePrivateDirectory(at: recoverySnapshotURL.deletingLastPathComponent())
  }

  public func snapshotActiveStateIfNeeded() throws {
    if try hasRecoverySnapshot() { return }
    let data = try Self.readPrivateAuthenticationFile(at: activeAuthenticationURL)
    try Self.validateAuthenticationPayload(data)
    try Self.writeNewPrivateFile(data, to: recoverySnapshotURL)
  }

  public func hasRecoverySnapshot() throws -> Bool {
    guard Self.fileExistsWithoutFollowingSymlink(recoverySnapshotURL) else { return false }
    _ = try Self.readPrivateAuthenticationFile(at: recoverySnapshotURL)
    return true
  }

  public func installAuthenticationFile(from sourceURL: URL) throws {
    let data = try Self.readPrivateAuthenticationFile(at: sourceURL.standardizedFileURL)
    try Self.validateAuthenticationPayload(data)
    try Self.replacePrivateFile(data, at: activeAuthenticationURL)
  }

  public func restoreRecoverySnapshot() throws {
    guard try hasRecoverySnapshot() else {
      throw DesktopIntegrationError.missingRecoverySnapshot
    }
    try installAuthenticationFile(from: recoverySnapshotURL)
  }

  /// Copies a private authentication file into a newly created private profile file.
  /// Both the source contents and destination directory are validated before writing.
  public static func archivePrivateAuthenticationFile(
    from sourceURL: URL,
    to destinationURL: URL
  ) throws {
    let source = sourceURL.standardizedFileURL
    let destination = destinationURL.standardizedFileURL
    let data = try readPrivateAuthenticationFile(at: source)
    try validateAuthenticationPayload(data)
    try preparePrivateDirectory(at: destination.deletingLastPathComponent())
    try writeNewPrivateFile(data, to: destination)
    try synchronizeDirectory(destination.deletingLastPathComponent())
  }

  /// Refreshes an existing private profile from the currently active authentication file.
  /// The replacement is atomic and never changes the source file.
  public static func synchronizePrivateAuthenticationFile(
    from sourceURL: URL,
    to destinationURL: URL
  ) throws {
    let source = sourceURL.standardizedFileURL
    let destination = destinationURL.standardizedFileURL
    let data = try readPrivateAuthenticationFile(at: source)
    try validateAuthenticationPayload(data)
    try preparePrivateDirectory(at: destination.deletingLastPathComponent())
    try replacePrivateFile(data, at: destination)
  }

  public static func readPrivateAuthenticationFile(at url: URL) throws -> Data {
    let descriptor = url.path.withCString { open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
    guard descriptor >= 0 else { throw DesktopIntegrationError.invalidAuthenticationFile }
    defer { close(descriptor) }

    var status = stat()
    guard fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_nlink == 1
    else {
      throw DesktopIntegrationError.insecureAuthenticationFile
    }
    guard status.st_mode & 0o777 == 0o600 else {
      throw DesktopIntegrationError.insecureAuthenticationFile
    }
    guard status.st_size >= 0, status.st_size <= maximumAuthenticationBytes else {
      throw DesktopIntegrationError.authenticationFileTooLarge
    }

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = read(descriptor, &buffer, buffer.count)
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        throw DesktopIntegrationError.invalidAuthenticationFile
      }
      guard result.count + count <= maximumAuthenticationBytes else {
        throw DesktopIntegrationError.authenticationFileTooLarge
      }
      result.append(buffer, count: count)
    }
    return result
  }

  public static func validateAuthenticationPayload(_ data: Data) throws {
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      object["tokens"] is [String: Any]
    else {
      throw DesktopIntegrationError.invalidAuthenticationPayload
    }
  }

  private static func replacePrivateFile(_ data: Data, at destinationURL: URL) throws {
    let directoryURL = destinationURL.deletingLastPathComponent()
    let temporaryURL = directoryURL.appendingPathComponent(
      ".switchgpt-auth-\(UUID().uuidString).tmp"
    )
    try writeNewPrivateFile(data, to: temporaryURL)
    var renamed = false
    defer {
      if !renamed { try? FileManager.default.removeItem(at: temporaryURL) }
    }
    guard
      temporaryURL.path.withCString({ source in
        destinationURL.path.withCString { destination in rename(source, destination) }
      }) == 0
    else {
      throw DesktopIntegrationError.invalidAuthenticationFile
    }
    renamed = true
    try synchronizeDirectory(directoryURL)
  }

  private static func writeNewPrivateFile(_ data: Data, to url: URL) throws {
    let descriptor = url.path.withCString {
      open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
    }
    guard descriptor >= 0 else { throw DesktopIntegrationError.invalidAuthenticationFile }
    defer { close(descriptor) }

    try data.withUnsafeBytes { rawBuffer in
      guard var address = rawBuffer.baseAddress else { return }
      var remaining = rawBuffer.count
      while remaining > 0 {
        let written = write(descriptor, address, remaining)
        if written < 0 {
          if errno == EINTR { continue }
          throw DesktopIntegrationError.invalidAuthenticationFile
        }
        remaining -= written
        address = address.advanced(by: written)
      }
    }
    guard fsync(descriptor) == 0 else {
      throw DesktopIntegrationError.invalidAuthenticationFile
    }
  }

  private static func preparePrivateDirectory(at url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      var status = stat()
      guard lstat(url.path, &status) == 0,
        status.st_mode & S_IFMT == S_IFDIR,
        status.st_uid == geteuid(),
        status.st_mode & 0o777 == 0o700
      else {
        throw DesktopIntegrationError.insecureAuthenticationFile
      }
      return
    }
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }

  private static func synchronizeDirectory(_ url: URL) throws {
    let descriptor = url.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC) }
    guard descriptor >= 0 else { throw DesktopIntegrationError.invalidAuthenticationFile }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw DesktopIntegrationError.invalidAuthenticationFile
    }
  }

  private static func fileExistsWithoutFollowingSymlink(_ url: URL) -> Bool {
    var status = stat()
    return lstat(url.path, &status) == 0
  }
}
