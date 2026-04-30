import XCTest
@testable import Merlin

@MainActor
final class DisabledSkillsTests: XCTestCase {

    private func makeTempDir() -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skills-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func makeSkill(name: String, in tempDir: URL) -> Skill {
        let dir = tempDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let frontmatter = "---\nname: \(name)\ndescription: test skill\n---\n"
        try? frontmatter.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return Skill.load(from: dir, isProjectScoped: false)!
    }

    func testDisabledSkillExcluded() {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let registry = SkillsRegistry(personalDir: tempDir, projectDir: nil)
        let skills = [makeSkill(name: "alpha", in: tempDir), makeSkill(name: "beta", in: tempDir)]
        let enabled = registry.enabledSkills(from: skills, disabledNames: ["beta"])
        XCTAssertEqual(enabled.map(\.name), ["alpha"])
    }

    func testEnabledSkillIncluded() {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let registry = SkillsRegistry(personalDir: tempDir, projectDir: nil)
        let skills = [makeSkill(name: "alpha", in: tempDir), makeSkill(name: "beta", in: tempDir)]
        let enabled = registry.enabledSkills(from: skills, disabledNames: [])
        XCTAssertEqual(Set(enabled.map(\.name)), Set(["alpha", "beta"]))
    }

    func testEmptyDisabledListReturnsAll() {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let registry = SkillsRegistry(personalDir: tempDir, projectDir: nil)
        let skills = [makeSkill(name: "a", in: tempDir), makeSkill(name: "b", in: tempDir), makeSkill(name: "c", in: tempDir)]
        let enabled = registry.enabledSkills(from: skills, disabledNames: [])
        XCTAssertEqual(enabled.count, 3)
    }

    func testAllDisabledReturnsEmpty() {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let registry = SkillsRegistry(personalDir: tempDir, projectDir: nil)
        let skills = [makeSkill(name: "a", in: tempDir), makeSkill(name: "b", in: tempDir)]
        let enabled = registry.enabledSkills(from: skills, disabledNames: ["a", "b"])
        XCTAssertTrue(enabled.isEmpty)
    }

    @MainActor
    func testContextManagerBlockOmitsDisabledSkill() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let ctx = ContextManager()
        let skillA = makeSkill(name: "review", in: tempDir)
        let skillB = makeSkill(name: "commit", in: tempDir)

        let block = ctx.buildSkillReinjectionBlock(
            skills: [skillA, skillB],
            disabledNames: ["commit"]
        )

        XCTAssertTrue(block.contains("review"), "Enabled skill should appear in block")
        XCTAssertFalse(block.contains("commit"), "Disabled skill should not appear in block")
    }
}
