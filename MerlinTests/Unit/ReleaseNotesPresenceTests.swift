import XCTest
@testable import Merlin

final class ReleaseNotesPresenceTests: XCTestCase {

    func testReleaseNotesFileExistsAndHasSections() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Unit
            .deletingLastPathComponent() // MerlinTests
            .deletingLastPathComponent() // repo root
        let releaseNotesURL = repoRoot.appendingPathComponent("RELEASE-v2.1.0.md")

        guard FileManager.default.fileExists(atPath: releaseNotesURL.path) else {
            XCTFail("RELEASE-v2.1.0.md is missing")
            return
        }

        let contents = try String(contentsOf: releaseNotesURL, encoding: .utf8)
        for header in ["## Summary", "## What's new", "## Internal changes", "## Migration"] {
            XCTAssertTrue(contents.contains(header), "Missing \(header)")
        }
    }
}
