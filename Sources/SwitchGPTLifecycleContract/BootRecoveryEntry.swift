import Foundation
import SwitchGPTSafetyCore

public enum BootRecoveryOutcome: String, Codable, Equatable, Sendable {
  case inactive
  case armedForReboot
  case rebootDeliveryRecorded
  case duplicateDeliveryDetected
  case sessionBusy
  case recovered
  case terminal
  case manualRecoveryRequired
  case unsafeState
  case invalidInvocation
}

public enum RebootDeliveryEntry {
  public static func run(
    recorder: PersistentActivationAttemptRecorder,
    evidenceStore: RebootDeliveryEvidenceStore,
    bootSession: BootSessionIdentifier
  ) -> BootRecoveryOutcome {
    do {
      guard try recorder.hasReservation(.registration) else {
        return .unsafeState
      }
      switch try evidenceStore.recordDelivery(on: bootSession) {
      case .inactive:
        return .inactive
      case .armedForFutureBoot:
        return .armedForReboot
      case .rebootDeliveryRecorded:
        return .rebootDeliveryRecorded
      case .duplicateDeliveryDetected:
        return .duplicateDeliveryDetected
      }
    } catch {
      return .unsafeState
    }
  }
}

public enum BootRecoveryEntry {
  public static let command = "recover-at-login"

  public static func run(
    arguments: [String],
    store: TransactionStore,
    desktop: TransactionDesktop
  ) -> BootRecoveryOutcome {
    guard arguments == [command] else { return .invalidInvocation }

    do {
      let result = try SwitchTransactionEngine(store: store, desktop: desktop)
        .recoverWithDisposition()
      if result.disposition == .observedTerminal {
        return result.record.phase == .manualRecoveryRequired ? .manualRecoveryRequired : .terminal
      }

      switch result.record.phase {
      case .rolledBack:
        return .recovered
      case .manualRecoveryRequired:
        return .manualRecoveryRequired
      case .committed:
        return .terminal
      default:
        return .unsafeState
      }
    } catch SafetyError.missingTransaction {
      return .inactive
    } catch {
      return .unsafeState
    }
  }
}
