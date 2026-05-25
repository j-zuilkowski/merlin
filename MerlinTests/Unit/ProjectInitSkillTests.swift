import XCTest

/// Tests that the project:init SKILL.md file is installed and well-formed.
/// These tests fail until task 259b writes the skill file.
final class ProjectInitSkillTests: XCTestCase {

    override func setUpWithError() throws {
        try skipUnlessLiveEnvironment(
            "project:* skill must be installed in ~/.merlin/skills")
    }

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-init/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-init/SKILL.md not found. Run task 259b.")
    }

    func testSkillHasTriggerSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"),
                      "SKILL.md must contain '## Trigger'")
    }

    func testSkillHasStepsSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Steps"),
                      "SKILL.md must contain '## Steps'")
    }

    func testSkillHasOutputSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Output"),
                      "SKILL.md must contain '## Output'")
    }

    func testSkillMentionsAdapter() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("adapter"),
                      "project:init SKILL.md should reference 'adapter'")
    }
}
