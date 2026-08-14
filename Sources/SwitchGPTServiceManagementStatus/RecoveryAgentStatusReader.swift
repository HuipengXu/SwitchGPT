import ServiceManagement
import SwitchGPTLifecycleContract

/// Read-only bridge to the system service state. This target intentionally exposes no mutation API.
public enum RecoveryAgentStatusReader {
  public static func read() -> RecoveryServiceStatus {
    map(
      SMAppService.agent(plistName: LifecycleBundleContract.launchAgentFileName).status
    )
  }

  private static func map(_ status: SMAppService.Status) -> RecoveryServiceStatus {
    switch status {
    case .notRegistered:
      return .notRegistered
    case .enabled:
      return .enabled
    case .requiresApproval:
      return .requiresApproval
    case .notFound:
      return .notFound
    @unknown default:
      return .unknown
    }
  }
}
