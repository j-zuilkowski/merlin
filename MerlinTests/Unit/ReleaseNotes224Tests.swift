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

    func testReleaseNotesContinueThroughCurrentPublishedVersion() throws {
        for version in ["2.3.0", "2.4.0"] {
            let notes = repoRoot().appendingPathComponent("RELEASE-v\(version).md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: notes.path),
                          "RELEASE-v\(version).md must exist at the repository root")

            let text = try String(contentsOf: notes, encoding: .utf8)
            for header in ["## Summary", "## What's new",
                           "## Internal changes", "## Migration"] {
                XCTAssertTrue(text.contains(header),
                              "RELEASE-v\(version).md must contain the '\(header)' section")
            }
        }
    }

    func testReadmeLinksUserFacingDocumentationAndCurrentReleaseNotes() throws {
        let readme = try String(contentsOf: repoRoot().appendingPathComponent("README.md"), encoding: .utf8)

        XCTAssertTrue(readme.contains("[User Guide](Merlin/Docs/UserGuide.md)"),
                      "README.md must link to the user guide with Markdown link syntax")
        XCTAssertTrue(readme.contains("[Developer Manual](Merlin/Docs/DeveloperManual.md)"),
                      "README.md must link to the developer manual with Markdown link syntax")
        XCTAssertTrue(readme.contains("[Release Notes v2.4.0](RELEASE-v2.4.0.md)"),
                      "README.md must link to the current release notes")
    }

    func testCurrentReleaseNotesEmbedPublicScreenshots() throws {
        let notes = try String(contentsOf: repoRoot().appendingPathComponent("RELEASE-v2.4.0.md"), encoding: .utf8)

        for screenshot in [
            "docs/assets/screenshots/v2.4.0/merlin-workspace.png",
            "docs/assets/screenshots/v2.4.0/kicad-schematic-editor.png",
            "docs/assets/screenshots/v2.4.0/kicad-pcb-editor.png",
            "docs/assets/screenshots/v2.4.0/kicad-3d-viewer.png",
        ] {
            XCTAssertTrue(notes.contains("](\(screenshot))"),
                          "RELEASE-v2.4.0.md must embed \(screenshot)")
        }
    }
}
