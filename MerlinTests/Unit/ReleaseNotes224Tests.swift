import XCTest
@testable import Merlin

final class ReleaseNotes224Tests: XCTestCase {

    /// Walks up from this test file to the repository root.
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // MerlinTests
            .deletingLastPathComponent()   // repo root
    }

    func testReleaseNotesFileExists() {
        let notes = repoRoot().appendingPathComponent("RELEASE-v2.2.4.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: notes.path),
                      "RELEASE-v2.2.4.md must exist at the repository root")
    }

    func testReleaseNotesHasRequiredSections() throws {
        let notes = repoRoot().appendingPathComponent("RELEASE-v2.2.4.md")
        let text = try String(contentsOf: notes, encoding: .utf8)

        for header in ["## Summary", "## What's new",
                       "## Internal changes", "## Migration"] {
            XCTAssertTrue(text.contains(header),
                          "RELEASE-v2.2.4.md must contain the '\(header)' section")
        }
    }
}
