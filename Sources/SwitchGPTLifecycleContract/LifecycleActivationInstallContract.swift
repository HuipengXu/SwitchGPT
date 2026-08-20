import Darwin
import Foundation

public enum LifecycleActivationInstallContractError: Error, Equatable, Sendable {
  case invalidInstallLocation
  case unsafeInstallLocation
}

public enum LifecycleActivationInstallContract {
  public static var expectedBundleURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Applications", isDirectory: true)
      .appendingPathComponent("SwitchGPTLifecycleValidation.app", isDirectory: true)
      .standardizedFileURL
  }

  public static func validate(bundleURL: URL) throws {
    try validate(bundleURL: bundleURL, expectedBundleURL: expectedBundleURL)
  }

  static func validate(bundleURL: URL, expectedBundleURL: URL) throws {
    let candidate = bundleURL.standardizedFileURL
    let expected = expectedBundleURL.standardizedFileURL
    guard candidate == expected else {
      throw LifecycleActivationInstallContractError.invalidInstallLocation
    }
    guard candidate.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath()
    else {
      throw LifecycleActivationInstallContractError.unsafeInstallLocation
    }

    var status = stat()
    guard
      candidate.path.withCString({ lstat($0, &status) }) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == geteuid(),
      status.st_mode & 0o022 == 0
    else {
      throw LifecycleActivationInstallContractError.unsafeInstallLocation
    }

    var parentStatus = stat()
    let parent = candidate.deletingLastPathComponent()
    guard
      parent.path.withCString({ lstat($0, &parentStatus) }) == 0,
      parentStatus.st_mode & S_IFMT == S_IFDIR,
      parentStatus.st_uid == geteuid(),
      parentStatus.st_mode & 0o022 == 0
    else {
      throw LifecycleActivationInstallContractError.unsafeInstallLocation
    }
  }
}
