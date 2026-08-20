import CoreFoundation
import Foundation

public enum LaunchAgentContractError: Error, Equatable, Sendable {
  case malformedPropertyList
  case unexpectedKeys
  case invalidLabel
  case invalidBundleProgram
  case invalidProgramArguments
  case runAtLoadRequired
  case launchOnlyOnceRequired
  case invalidSessionType
}

public enum LaunchAgentContract {
  public static let label = "com.switchgpt.recovery-at-login"
  public static let bundleProgram = "Contents/Library/LaunchServices/SwitchGPTBootRecovery"
  public static let programArguments = ["SwitchGPTBootRecovery", BootRecoveryEntry.command]
  public static let sessionType = "Aqua"

  public static let allowedKeys: Set<String> = [
    "Label",
    "BundleProgram",
    "ProgramArguments",
    "RunAtLoad",
    "LaunchOnlyOnce",
    "LimitLoadToSessionType",
  ]

  public static func canonicalPropertyListData(format: PropertyListSerialization.PropertyListFormat)
    throws -> Data
  {
    try PropertyListSerialization.data(
      fromPropertyList: canonicalDictionary,
      format: format,
      options: 0
    )
  }

  public static func validate(data: Data) throws {
    let propertyList: Any
    do {
      propertyList = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      )
    } catch {
      throw LaunchAgentContractError.malformedPropertyList
    }
    guard let dictionary = propertyList as? [String: Any] else {
      throw LaunchAgentContractError.malformedPropertyList
    }
    try validate(dictionary: dictionary)
  }

  public static func validate(dictionary: [String: Any]) throws {
    guard Set(dictionary.keys) == allowedKeys else {
      throw LaunchAgentContractError.unexpectedKeys
    }
    guard dictionary["Label"] as? String == label else {
      throw LaunchAgentContractError.invalidLabel
    }
    guard dictionary["BundleProgram"] as? String == bundleProgram else {
      throw LaunchAgentContractError.invalidBundleProgram
    }
    guard dictionary["ProgramArguments"] as? [String] == programArguments else {
      throw LaunchAgentContractError.invalidProgramArguments
    }
    guard isTrueBoolean(dictionary["RunAtLoad"]) else {
      throw LaunchAgentContractError.runAtLoadRequired
    }
    guard isTrueBoolean(dictionary["LaunchOnlyOnce"]) else {
      throw LaunchAgentContractError.launchOnlyOnceRequired
    }
    guard dictionary["LimitLoadToSessionType"] as? String == sessionType else {
      throw LaunchAgentContractError.invalidSessionType
    }
  }

  private static var canonicalDictionary: [String: Any] {
    [
      "Label": label,
      "BundleProgram": bundleProgram,
      "ProgramArguments": programArguments,
      "RunAtLoad": true,
      "LaunchOnlyOnce": true,
      "LimitLoadToSessionType": sessionType,
    ]
  }

  private static func isTrueBoolean(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID() && number.boolValue
  }
}
