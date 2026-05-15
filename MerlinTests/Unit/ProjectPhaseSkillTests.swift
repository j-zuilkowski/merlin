import XCTest

final class ProjectPhaseSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-phase/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-phase/SKILL.md not found. Run phase 260b.")
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
        XCTAssertTrue(text.contains("NNa") || text.contains("phase-NNa"),
                      "SKILL.md should reference NNa phase files")
        XCTAssertTrue(text.contains("NNb") || text.contains("phase-NNb"),
                      "SKILL.md should reference NNb phase files")
    }
}
