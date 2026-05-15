import XCTest

final class ProjectReleaseSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-release/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-release/SKILL.md not found. Run phase 262b.")
    }

    func testSkillHasRequiredSections() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"))
        XCTAssertTrue(text.contains("## Steps"))
        XCTAssertTrue(text.contains("## Output"))
    }

    func testSkillMentionsReleaseGate() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("release gate"),
                      "project:release should mention 'release gate'")
    }

    func testSkillMentionsReleaseNotes() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("RELEASE-v"),
                      "project:release should mention RELEASE-vX.Y.Z.md")
    }

    func testSkillMentionsVersionBump() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("version bump") ||
                      text.lowercased().contains("bump version"),
                      "project:release should mention version bump")
    }

    func testSkillMentionsGhRelease() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("gh release create"),
                      "project:release should mention 'gh release create'")
    }
}
