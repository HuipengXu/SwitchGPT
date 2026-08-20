import SwitchGPTSafetyCore

/// The sole production bridge from desktop integration into the safety transaction engine.
/// UI targets submit validated dependencies here and cannot invoke a transaction directly.
public enum IndependentDesktopSwitchRunner {
  @discardableResult
  public static func perform(
    store: TransactionStore,
    desktop: TransactionDesktop,
    hostEvidence: SupervisorHostEvidence,
    recoverySupervisor: OneShotRecoverySupervisor,
    source: IdentityID,
    target: IdentityID
  ) throws -> TransactionRecord {
    try IndependentSwitchSupervisor(
      store: store,
      desktop: desktop,
      hostEvidence: hostEvidence,
      recoverySupervisor: recoverySupervisor
    ).beginSwitch(from: source, to: target)
  }
}
