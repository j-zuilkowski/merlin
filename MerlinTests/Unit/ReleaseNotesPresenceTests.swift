import XCTest

final class ReleaseNotesPresenceTests: XCTestCase {

    /// Path derived from the test bundle — walk up to the project root.
    private func projectRoot() throws -> URL {
        // Test bundle is typically at <project>/build/... or DerivedData
        // Walk up from __FILE__ compile-time constant
        var url = URL(fileURLWithPath: #file)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            let candidate = url.appendingPathComponent("RELEASE-v2.2.0.md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
        }
        throw XCTestError(.failureWhileWaiting,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Could not find project root containing RELEASE-v2.2.0.md"])
    }

    func testReleaseNotesExist() throws {
        let root = try projectRoot()
        let notesPath = root.appendingPathComponent("RELEASE-v2.2.0.md").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesPath),
                      "RELEASE-v2.2.0.md not found at project root. Run task 265b.")
    }

    func testReleaseNotesHaveWhatsNewSection() throws {
        let root = try projectRoot()
        let text = try String(
            contentsOf: root.appendingPathComponent("RELEASE-v2.2.0.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("## What's New"),
                      "RELEASE-v2.2.0.md must contain '## What's New'")
    }

    func testReleaseNotesHaveKnownIssuesSection() throws {
        let root = try projectRoot()
        let text = try String(
            contentsOf: root.appendingPathComponent("RELEASE-v2.2.0.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("## Known Issues"),
                      "RELEASE-v2.2.0.md must contain '## Known Issues'")
    }

    func testReleaseNotesHaveUpgradeNotesSection() throws {
        let root = try projectRoot()
        let text = try String(
            contentsOf: root.appendingPathComponent("RELEASE-v2.2.0.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("## Upgrade Notes"),
                      "RELEASE-v2.2.0.md must contain '## Upgrade Notes'")
    }
}
