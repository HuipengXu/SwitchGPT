import Foundation

public enum CodexRateLimitDecoder {
  public static func decodeUsage(from data: Data) throws -> AccountUsage {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let root = object as? [String: Any] else {
      throw QuotaReadingError.invalidProtocolResponse
    }

    let limit = selectLimit(from: root)
    guard let primary = limit["primary"] as? [String: Any] else {
      throw QuotaReadingError.missingRateLimit
    }

    let weekly = try decodeWindow(primary)
    let fiveHour: UsageWindow?
    if let secondary = limit["secondary"] as? [String: Any] {
      fiveHour = try decodeWindow(secondary)
    } else {
      fiveHour = nil
    }

    return AccountUsage(
      weekly: weekly,
      fiveHour: fiveHour,
      credits: decodeCredits(limit["credits"]),
      creditsWereLoaded: true
    )
  }

  private static func selectLimit(from root: [String: Any]) -> [String: Any] {
    if let byID = root["rateLimitsByLimitId"] as? [String: Any],
      let codex = byID["codex"] as? [String: Any]
    {
      return codex
    }
    if let rateLimits = root["rateLimits"] as? [String: Any] {
      return rateLimits
    }
    return root
  }

  private static func decodeWindow(_ object: [String: Any]) throws -> UsageWindow {
    guard let used = number(from: object["usedPercent"]),
      let reset = number(from: object["resetsAt"])
    else {
      throw QuotaReadingError.invalidProtocolResponse
    }

    let resetSeconds = reset > 10_000_000_000 ? reset / 1_000 : reset
    return UsageWindow(
      usedPercent: Int(used.rounded()),
      resetAt: Date(timeIntervalSince1970: resetSeconds)
    )
  }

  private static func number(from value: Any?) -> Double? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let string = value as? String {
      return Double(string)
    }
    return nil
  }

  private static func decodeCredits(_ value: Any?) -> CreditBalance? {
    guard let object = value as? [String: Any],
      let hasCredits = object["hasCredits"] as? Bool,
      let unlimited = object["unlimited"] as? Bool
    else {
      return nil
    }

    let points = decimal(from: object["balance"])
    return CreditBalance(
      hasCredits: hasCredits,
      unlimited: unlimited,
      points: points.flatMap { $0 >= 0 ? $0 : nil }
    )
  }

  private static func decimal(from value: Any?) -> Decimal? {
    let rawValue: String
    if let string = value as? String {
      rawValue = string.trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let number = value as? NSNumber {
      rawValue = number.stringValue
    } else {
      return nil
    }

    guard !rawValue.isEmpty else { return nil }
    return Decimal(string: rawValue, locale: Locale(identifier: "en_US_POSIX"))
  }
}
