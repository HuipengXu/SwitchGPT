import Darwin
import Foundation

public final class TransactionLock {
  private var fileDescriptor: Int32

  public convenience init(url: URL) throws {
    try self.init(url: url, waitUntilAvailable: false)
  }

  init(url: URL, waitUntilAvailable: Bool) throws {
    try SecureFileIO.validatePrivateDirectory(at: url.deletingLastPathComponent())

    var created = false
    fileDescriptor = url.path.withCString {
      open(
        $0,
        O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
        SecureFileIO.privateFileMode
      )
    }
    if fileDescriptor >= 0 {
      created = true
    } else if errno == EEXIST {
      fileDescriptor = url.path.withCString {
        open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
      }
    }
    guard fileDescriptor >= 0 else {
      if errno == ELOOP { throw SafetyError.unsafeStorage }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    do {
      guard !created || fchmod(fileDescriptor, SecureFileIO.privateFileMode) == 0 else {
        throw SecureFileIO.currentPOSIXError()
      }
      try SecureFileIO.validateOpenPrivateRegularFile(fileDescriptor)
    } catch {
      close(fileDescriptor)
      fileDescriptor = -1
      throw error
    }

    let operation = waitUntilAvailable ? LOCK_EX : LOCK_EX | LOCK_NB
    while flock(fileDescriptor, operation) != 0 {
      if errno == EINTR { continue }
      let lockError = errno
      close(fileDescriptor)
      fileDescriptor = -1
      if !waitUntilAvailable, lockError == EWOULDBLOCK {
        throw SafetyError.lockUnavailable
      }
      throw POSIXError(POSIXErrorCode(rawValue: lockError) ?? .EIO)
    }
  }

  deinit {
    release()
  }

  public func release() {
    guard fileDescriptor >= 0 else { return }
    _ = flock(fileDescriptor, LOCK_UN)
    close(fileDescriptor)
    fileDescriptor = -1
  }
}
