import XCTest

final class ProjectTaskSkillTests: XCTestCase {

    override func setUpWithError() throws {
        try skipUnlessLiveEnvironment(
            "project:* skill must be installed in ~/.merlin/skills")
    }

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-task/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-task/SKILL.md not found. Run task 260b.")
    }

    func testSkillHasTriggerSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"))
    }

    func testSkillHasStepsSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Steps"))
    }

    func testSkillHasOutputSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Output"))
    }

    func testSkillMentionsNNaAndNNb() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("NNa") || text.contains("task-NNa"),
                      "SKILL.md should reference NNa task files")
        XCTAssertTrue(text.contains("NNb") || text.contains("task-NNb"),
                      "SKILL.md should reference NNb task files")
    }
}
