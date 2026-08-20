import Foundation
import SwitchGPTSafetyCore

/// Holds an exclusive, non-blocking lock for one lifecycle validation session.
/// A crashed process releases the kernel lock, while the private lock file remains reusable.
public final class LifecycleActivationSessionLock {
  private let lock: TransactionLock

  public init(sessionURL: URL) throws {
    lock = try TransactionLock(
      url: sessionURL.appendingPathComponent("activation-session.lock")
    )
  }

  public func release() {
    lock.release()
  }
}
