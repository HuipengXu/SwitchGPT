import Darwin
import Foundation
import Security

public enum SupervisorHostCollectionError: Error, Equatable, Sendable {
  case missingBundle
  case missingExecutable
  case signingInspectionFailed
  case processInspectionFailed
}

public struct SupervisorRuntimeSnapshot: Equatable, Sendable {
  public let bundleIdentifier: String
  public let bundleURL: URL
  public let executableURL: URL
  public let signatureEvidence: SupervisorSignatureEvidence
  public let ancestorExecutableURLs: [URL]

  public init(
    bundleIdentifier: String,
    bundleURL: URL,
    executableURL: URL,
    signatureEvidence: SupervisorSignatureEvidence,
    ancestorExecutableURLs: [URL]
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.bundleURL = bundleURL
    self.executableURL = executableURL
    self.signatureEvidence = signatureEvidence
    self.ancestorExecutableURLs = ancestorExecutableURLs
  }
}

public struct SupervisorHostConfiguration: Equatable, Sendable {
  public let expectedHostBundleIdentifier: String
  public let expectedHostTeamIdentifier: String
  public let targetBundleIdentifier: String
  public let targetBundleURL: URL

  public init(
    expectedHostBundleIdentifier: String,
    expectedHostTeamIdentifier: String,
    targetBundleIdentifier: String,
    targetBundleURL: URL
  ) {
    self.expectedHostBundleIdentifier = expectedHostBundleIdentifier
    self.expectedHostTeamIdentifier = expectedHostTeamIdentifier
    self.targetBundleIdentifier = targetBundleIdentifier
    self.targetBundleURL = targetBundleURL
  }
}

public enum SystemSupervisorHostEvidenceCollector {
  public static func collect(
    configuration: SupervisorHostConfiguration,
    bundle: Bundle = .main
  ) throws -> SupervisorHostEvidence {
    guard let bundleIdentifier = bundle.bundleIdentifier else {
      throw SupervisorHostCollectionError.missingBundle
    }
    guard let executableURL = bundle.executableURL else {
      throw SupervisorHostCollectionError.missingExecutable
    }
    let snapshot = SupervisorRuntimeSnapshot(
      bundleIdentifier: bundleIdentifier,
      bundleURL: bundle.bundleURL,
      executableURL: executableURL,
      signatureEvidence: try currentSignatureEvidence(executableURL: executableURL),
      ancestorExecutableURLs: try currentAncestorExecutableURLs()
    )
    return evidence(from: snapshot, configuration: configuration)
  }

  public static func evidence(
    from snapshot: SupervisorRuntimeSnapshot,
    configuration: SupervisorHostConfiguration
  ) -> SupervisorHostEvidence {
    SupervisorHostEvidence(
      hostBundleIdentifier: snapshot.bundleIdentifier,
      expectedHostBundleIdentifier: configuration.expectedHostBundleIdentifier,
      targetBundleIdentifier: configuration.targetBundleIdentifier,
      expectedHostTeamIdentifier: configuration.expectedHostTeamIdentifier,
      signatureEvidence: snapshot.signatureEvidence,
      executableURL: snapshot.executableURL,
      expectedHostBundleURL: snapshot.bundleURL,
      targetBundleURL: configuration.targetBundleURL,
      ancestorExecutableURLs: snapshot.ancestorExecutableURLs,
      launchMechanism: .application
    )
  }

  private static func currentSignatureEvidence(
    executableURL: URL
  ) throws -> SupervisorSignatureEvidence {
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(executableURL as CFURL, [], &code) == errSecSuccess,
      let code
    else {
      throw SupervisorHostCollectionError.signingInspectionFailed
    }
    guard
      SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
        == errSecSuccess
    else {
      return .invalid
    }

    var signingInformation: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &signingInformation
      ) == errSecSuccess,
      let information = signingInformation as? [CFString: Any],
      let teamIdentifier = information[kSecCodeInfoTeamIdentifier] as? String,
      let signingIdentifier = information[kSecCodeInfoIdentifier] as? String
    else {
      return .invalid
    }
    return .verified(
      teamIdentifier: teamIdentifier,
      signingIdentifier: signingIdentifier
    )
  }

  private static func currentAncestorExecutableURLs() throws -> [URL] {
    var result: [URL] = []
    var seen = Set<pid_t>()
    var processID = getppid()

    while processID > 1, seen.insert(processID).inserted, result.count < 64 {
      var pathBuffer = [CChar](repeating: 0, count: 4096)
      let pathLength = proc_pidpath(processID, &pathBuffer, UInt32(pathBuffer.count))
      guard pathLength > 0 else {
        throw SupervisorHostCollectionError.processInspectionFailed
      }
      let pathBytes = pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
      result.append(URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self)))

      var processInfo = proc_bsdinfo()
      let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
      let actualSize = proc_pidinfo(
        processID,
        PROC_PIDTBSDINFO,
        0,
        &processInfo,
        expectedSize
      )
      guard actualSize == expectedSize else {
        throw SupervisorHostCollectionError.processInspectionFailed
      }
      processID = pid_t(processInfo.pbi_ppid)
    }
    return result
  }
}
