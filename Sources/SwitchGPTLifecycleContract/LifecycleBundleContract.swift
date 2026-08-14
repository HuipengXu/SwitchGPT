import CoreFoundation
import Darwin
import Foundation

public enum LifecycleBundleContractError: Error, Equatable, Sendable {
  case unsafeFileSystemObject(String)
  case unexpectedDirectoryContents(String)
  case malformedInfoPropertyList
  case unexpectedInfoKeys
  case invalidInfoValue(String)
  case invalidLaunchAgent
}

public enum LifecycleBundleContract {
  public static let bundleIdentifier = "com.switchgpt.lifecycle-validation"
  public static let bundleName = "SwitchGPTLifecycleValidation"
  public static let hostExecutableName = "SwitchGPTLifecycleHost"
  public static let recoveryExecutableName = "SwitchGPTBootRecovery"
  public static let launchAgentFileName = "com.switchgpt.recovery-at-login.plist"

  private static let infoKeys: Set<String> = [
    "CFBundleDevelopmentRegion",
    "CFBundleDisplayName",
    "CFBundleExecutable",
    "CFBundleIdentifier",
    "CFBundleInfoDictionaryVersion",
    "CFBundleName",
    "CFBundlePackageType",
    "CFBundleShortVersionString",
    "CFBundleVersion",
    "LSMinimumSystemVersion",
    "LSUIElement",
    "NSPrincipalClass",
  ]

  public static func canonicalInfoPropertyListData(
    format: PropertyListSerialization.PropertyListFormat
  ) throws -> Data {
    try PropertyListSerialization.data(
      fromPropertyList: canonicalInfoDictionary,
      format: format,
      options: 0
    )
  }

  public static func validate(bundleURL: URL) throws {
    let bundle = bundleURL.standardizedFileURL
    let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
    let info = contents.appendingPathComponent("Info.plist")
    let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
    let host = macOS.appendingPathComponent(hostExecutableName)
    let library = contents.appendingPathComponent("Library", isDirectory: true)
    let launchAgents = library.appendingPathComponent("LaunchAgents", isDirectory: true)
    let launchAgent = launchAgents.appendingPathComponent(launchAgentFileName)
    let launchServices = library.appendingPathComponent("LaunchServices", isDirectory: true)
    let recovery = launchServices.appendingPathComponent(recoveryExecutableName)
    let codeSignature = contents.appendingPathComponent("_CodeSignature", isDirectory: true)

    try requireDirectory(bundle, label: "bundle")
    try requireExactContents(bundle, expected: ["Contents"], label: "bundle")
    try requireDirectory(contents, label: "Contents")

    let requiredContents: Set<String> = ["Info.plist", "Library", "MacOS"]
    let actualContents = try directoryContents(contents, label: "Contents")
    guard
      actualContents == requiredContents
        || actualContents == requiredContents.union(["_CodeSignature"])
    else {
      throw LifecycleBundleContractError.unexpectedDirectoryContents("Contents")
    }
    if actualContents.contains("_CodeSignature") {
      try requireDirectory(codeSignature, label: "Contents/_CodeSignature")
    }

    try requireRegularFile(info, executable: false, label: "Contents/Info.plist")
    try validateInfo(data: try Data(contentsOf: info))

    try requireDirectory(macOS, label: "Contents/MacOS")
    try requireExactContents(macOS, expected: [hostExecutableName], label: "Contents/MacOS")
    try requireRegularFile(host, executable: true, label: "Contents/MacOS/host")

    try requireDirectory(library, label: "Contents/Library")
    try requireExactContents(
      library,
      expected: ["LaunchAgents", "LaunchServices"],
      label: "Contents/Library"
    )
    try requireDirectory(launchAgents, label: "Contents/Library/LaunchAgents")
    try requireExactContents(
      launchAgents,
      expected: [launchAgentFileName],
      label: "Contents/Library/LaunchAgents"
    )
    try requireRegularFile(
      launchAgent,
      executable: false,
      label: "Contents/Library/LaunchAgents/recovery plist"
    )
    do {
      try LaunchAgentContract.validate(data: Data(contentsOf: launchAgent))
    } catch {
      throw LifecycleBundleContractError.invalidLaunchAgent
    }

    try requireDirectory(launchServices, label: "Contents/Library/LaunchServices")
    try requireExactContents(
      launchServices,
      expected: [recoveryExecutableName],
      label: "Contents/Library/LaunchServices"
    )
    try requireRegularFile(
      recovery,
      executable: true,
      label: "Contents/Library/LaunchServices/recovery"
    )
  }

  public static func validateInfo(data: Data) throws {
    let propertyList: Any
    do {
      propertyList = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      )
    } catch {
      throw LifecycleBundleContractError.malformedInfoPropertyList
    }
    guard let dictionary = propertyList as? [String: Any] else {
      throw LifecycleBundleContractError.malformedInfoPropertyList
    }
    guard Set(dictionary.keys) == infoKeys else {
      throw LifecycleBundleContractError.unexpectedInfoKeys
    }

    for (key, expected) in canonicalInfoDictionary where key != "LSUIElement" {
      guard dictionary[key] as? String == expected as? String else {
        throw LifecycleBundleContractError.invalidInfoValue(key)
      }
    }
    guard isTrueBoolean(dictionary["LSUIElement"]) else {
      throw LifecycleBundleContractError.invalidInfoValue("LSUIElement")
    }
  }

  private static var canonicalInfoDictionary: [String: Any] {
    [
      "CFBundleDevelopmentRegion": "en",
      "CFBundleDisplayName": "SwitchGPT Lifecycle Validation",
      "CFBundleExecutable": hostExecutableName,
      "CFBundleIdentifier": bundleIdentifier,
      "CFBundleInfoDictionaryVersion": "6.0",
      "CFBundleName": bundleName,
      "CFBundlePackageType": "APPL",
      "CFBundleShortVersionString": "0.0.1",
      "CFBundleVersion": "1",
      "LSMinimumSystemVersion": "14.0",
      "LSUIElement": true,
      "NSPrincipalClass": "NSApplication",
    ]
  }

  private static func requireExactContents(
    _ url: URL,
    expected: Set<String>,
    label: String
  ) throws {
    guard try directoryContents(url, label: label) == expected else {
      throw LifecycleBundleContractError.unexpectedDirectoryContents(label)
    }
  }

  private static func directoryContents(_ url: URL, label: String) throws -> Set<String> {
    do {
      return Set(try FileManager.default.contentsOfDirectory(atPath: url.path))
    } catch {
      throw LifecycleBundleContractError.unsafeFileSystemObject(label)
    }
  }

  private static func requireDirectory(_ url: URL, label: String) throws {
    let status = try fileStatus(at: url, label: label)
    guard status.st_mode & S_IFMT == S_IFDIR else {
      throw LifecycleBundleContractError.unsafeFileSystemObject(label)
    }
  }

  private static func requireRegularFile(_ url: URL, executable: Bool, label: String) throws {
    let status = try fileStatus(at: url, label: label)
    guard status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1 else {
      throw LifecycleBundleContractError.unsafeFileSystemObject(label)
    }
    if executable, status.st_mode & 0o111 == 0 {
      throw LifecycleBundleContractError.unsafeFileSystemObject(label)
    }
  }

  private static func fileStatus(at url: URL, label: String) throws -> stat {
    var status = stat()
    guard url.path.withCString({ lstat($0, &status) }) == 0 else {
      throw LifecycleBundleContractError.unsafeFileSystemObject(label)
    }
    return status
  }

  private static func isTrueBoolean(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID() && number.boolValue
  }
}
