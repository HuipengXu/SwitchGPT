import Foundation
import XCTest

final class RuntimeControlSurfaceTests: XCTestCase {
  private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  func testRuntimeControlSurfacesDoNotUseRetiredSubmittedJobs() throws {
    let forbiddenCommand = "launchctl" + " submit"
    let roots = ["App", "Lifecycle", "Scripts", "Sources", "script"]
      .map(repositoryRoot.appendingPathComponent)

    for root in roots where FileManager.default.fileExists(atPath: root.path) {
      guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      ) else {
        XCTFail("Unable to enumerate runtime control surface: \(root.path)")
        continue
      }

      for case let fileURL as URL in enumerator {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
        XCTAssertFalse(
          contents.contains(forbiddenCommand),
          "Retired submitted-job control is forbidden in runtime surfaces: \(fileURL.path)"
        )
      }
    }
  }
}
