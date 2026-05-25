import XCTest

final class ProjectReviseSkillTests: XCTestCase {

    override func setUpWithError() throws {
        try skipUnlessLiveEnvironment(
            "project:* skill must be installed in ~/.merlin/skills")
    }

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-revise/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-revise/SKILL.md not found. Run task 261b.")
    }

    func testSkillHasRequiredSections() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"))
        XCTAssertTrue(text.contains("## Steps"))
        XCTAssertTrue(text.contains("## Output"))
    }

    func testSkillMentionsScan() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("scan") ||
                      text.contains("DisciplineEngine"),
                      "project:revise should mention scanning for drift")
    }

    func testSkillMentionsDismiss() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("dismiss") ||
                      text.lowercased().contains("defer"),
                      "project:revise should mention dismiss/defer workflow")
    }
}
