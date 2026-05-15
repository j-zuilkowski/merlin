import XCTest

final class ProjectAdoptSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-adopt/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-adopt/SKILL.md not found. Run phase 263b.")
    }

    func testSkillHasRequiredSections() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"))
        XCTAssertTrue(text.contains("## Steps"))
        XCTAssertTrue(text.contains("## Output"))
    }

    func testSkillMentionsBaseline() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("baseline"),
                      "project:adopt should mention baseline")
    }

    func testSkillMentionsManualCoverageBaseline() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("manual_coverage_baseline") ||
                      text.lowercased().contains("coverage baseline"),
                      "project:adopt should mention manual coverage baseline")
    }

    func testSkillMentionsExistingProject() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("existing project") ||
                      text.lowercased().contains("existing codebase"),
                      "project:adopt should target existing projects")
    }
}
