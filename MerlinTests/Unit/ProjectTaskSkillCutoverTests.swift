import XCTest

final class ProjectTaskSkillCutoverTests: XCTestCase {
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

    func testProjectTaskSkillIsCanonicalCommand() throws {
        XCTAssertTrue(fileExists("Merlin/Skills/Builtin/project-task/SKILL.md"))
        XCTAssertFalse(fileExists("Merlin/Skills/Builtin/project-phase/SKILL.md"))

        let text = try read("Merlin/Skills/Builtin/project-task/SKILL.md")
        XCTAssertTrue(text.contains("# project:task"))
        XCTAssertTrue(text.contains("/project:task"))
        assertNoLegacyArtifactReferences(text, file: "project-task")
        XCTAssertTrue(text.contains("tasks/task-NNa-<name>-tests.md"))
        XCTAssertTrue(text.contains("New surface introduced in task NNb:"))
    }

    func testProjectSkillsScaffoldAndValidateSddArtifactsOnly() throws {
        for path in [
            "Merlin/Skills/Builtin/project-init/SKILL.md",
            "Merlin/Skills/Builtin/project-adopt/SKILL.md",
            "Merlin/Skills/Builtin/project-revise/SKILL.md",
            "Merlin/Skills/Builtin/project-release/SKILL.md"
        ] {
            let text = try read(path)
            XCTAssertTrue(text.contains("constitution.md"), "\(path) should mention constitution.md")
            XCTAssertTrue(text.contains("spec.md"), "\(path) should mention spec.md")
            XCTAssertTrue(text.contains("tasks/"), "\(path) should mention tasks/")
            assertNoLegacyArtifactReferences(text, file: path)
        }
    }

    private func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(relativePath).path)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func assertNoLegacyArtifactReferences(_ text: String, file: String) {
        for forbidden in ["CLAUDE.md", "architecture.md", "phases/", "phase-", "/project:phase", "project-phase"] {
            XCTAssertFalse(text.contains(forbidden), "\(file) still contains \(forbidden)")
        }
    }
}
