import XCTest

/// Tests that the project:init skill scaffolds vision.md as the idea launchpad.
/// These tests build clean but FAIL at runtime until task 288b updates the skill.
final class ProjectVisionLaunchpadTests: XCTestCase {

    private var repoRoot: URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != current.deletingLastPathComponent().path {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("project.yml").path
            ) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private var skillPath: String {
        repoRoot.appendingPathComponent("Merlin/Skills/Builtin/project-init/SKILL.md").path
    }

    private var adoptSkillPath: String {
        repoRoot.appendingPathComponent("Merlin/Skills/Builtin/project-adopt/SKILL.md").path
    }

    private func skillBody() throws -> String {
        try String(contentsOfFile: skillPath, encoding: .utf8)
    }

    private func adoptSkillBody() throws -> String {
        try String(contentsOfFile: adoptSkillPath, encoding: .utf8)
    }

    func testProjectInitSkillExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "project-init SKILL.md not found — task 259b must have run first.")
    }

    func testProjectInitScaffoldsVisionDoc() throws {
        let body = try skillBody()
        XCTAssertTrue(body.contains("vision.md"),
                      "project:init must scaffold vision.md as part of the doc set.")
    }

    func testProjectInitSeedsTheInitialIdea() throws {
        // The launchpad is seeded at scaffold time — init captures the project idea
        // and writes it into vision.md's Active section.
        let body = try skillBody().lowercased()
        XCTAssertTrue(body.contains("## active") || body.contains("active section"),
                      "vision.md scaffold must seed an Active section.")
        XCTAssertTrue(body.contains("deferred"),
                      "vision.md scaffold must include a Deferred section.")
    }

    func testProjectInitDocumentsThePipeline() throws {
        // The vision -> spec -> task -> code pipeline must be stated in the skill
        // so the discipline workflow is explicit.
        let body = try skillBody().lowercased()
        let mentionsPipeline =
            body.contains("vision") && body.contains("spec")
            && body.contains("task") && body.contains("code")
        XCTAssertTrue(mentionsPipeline,
                      "project:init must document the vision->spec->task->code pipeline.")
    }

    func testProjectAdoptIncorporatesExistingVisionDoc() throws {
        // Adopting an existing project must recognise an existing vision.md rather than
        // ignore or clobber it, and give a vision-less project the launchpad scaffold.
        XCTAssertTrue(FileManager.default.fileExists(atPath: adoptSkillPath),
                      "project-adopt SKILL.md not found — task 263b must have run first.")
        let body = try adoptSkillBody()
        XCTAssertTrue(body.contains("vision.md"),
                      "project:adopt must incorporate an existing vision.md.")
    }
}
