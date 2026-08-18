import Foundation

/// Refreshes promptly when the user is looking at usage, while keeping idle
/// background reads deliberately infrequent.
enum UsageRefreshPolicy {
  static let dashboardVisibleMaxAge: TimeInterval = 5 * 60
  static let menuOpenMaxAge: TimeInterval = 0
  static let backgroundInterval: Duration = .seconds(3 * 60 * 60)
  static let backgroundMaxAge: TimeInterval = 3 * 60 * 60
}
