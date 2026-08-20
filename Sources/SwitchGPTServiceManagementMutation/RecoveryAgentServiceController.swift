import ServiceManagement
import SwitchGPTLifecycleContract
import SwitchGPTServiceManagementStatus

/// Minimal system mutation bridge kept in a target that the lifecycle host does not link.
/// Retry, approval handling, preflight, and durable attempt budgets belong to
/// `LifecycleActivationController`; this type performs exactly the requested API call.
public final class RecoveryAgentServiceController: RecoveryServiceControlling {
  private let service: SMAppService

  public init() {
    service = SMAppService.agent(
      plistName: LifecycleBundleContract.launchAgentFileName
    )
  }

  public func readStatus() throws -> RecoveryServiceStatus {
    RecoveryAgentStatusReader.read()
  }

  public func register() throws {
    try service.register()
  }

  public func unregister() throws {
    try service.unregister()
  }
}
