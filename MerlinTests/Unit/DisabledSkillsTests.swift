import XCTest
@testable import Merlin

@MainActor
final class DisabledSkillsTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skills-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeSkill(name: String) -> Skill {
        let dir = tempDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let frontmatter = "---\nname: \(name)\ndescription: test skill\n---\n"
        try? frontmatter.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return Skill.load(from: dir, isProjectScoped: false)!
    }

    func testDisabledSkillExcluded() {
        let registry = SkillsRegistry(personalDir: tempDir, projectDir: nil)
        let skills = [makeSkill(name: "alpha"), makeSkill(name: "beta")]
        let enabled = registry.enabledSkills(from: skills, disabledNames: ["beta"])
        XCTAssertEqual(enabled.map(\.name), ["alpha"])
    }

    func testEnabledSkillIncluded() {
        let registry = SkillsRegistry(personalDir: tempDir, projectDir: nil)
        let skills = [makeSkill(name: "alpha"), makeSkill(name: "beta")]
        let enabled = registry.enabledSkills(from: skills, disabledNames: [])
        XCTAssertEqual(Set(enabled.map(\.name)), Set(["alpha", "beta"]))
    }

    func testEmptyDisabledListReturnsAll() {
        let registry = SkillsRegistry(personalDir: tempDir, projectDir: nil)
        let skills = [makeSkill(name: "a"), makeSkill(name: "b"), makeSkill(name: "c")]
        let enabled = registry.enabledSkills(from: skills, disabledNames: [])
        XCTAssertEqual(enabled.count, 3)
    }

    func testAllDisabledReturnsEmpty() {
        let registry = SkillsRegistry(personalDir: tempDir, projectDir: nil)
        let skills = [makeSkill(name: "a"), makeSkill(name: "b")]
        let enabled = registry.enabledSkills(from: skills, disabledNames: ["a", "b"])
        XCTAssertTrue(enabled.isEmpty)
    }

    @MainActor
    func testContextManagerBlockOmitsDisabledSkill() throws {
        let ctx = ContextManager()
        let skillA = makeSkill(name: "review")
        let skillB = makeSkill(name: "commit")

        let block = ctx.buildSkillReinjectionBlock(
            skills: [skillA, skillB],
            disabledNames: ["commit"]
        )

        XCTAssertTrue(block.contains("review"), "Enabled skill should appear in block")
        XCTAssertFalse(block.contains("commit"), "Disabled skill should not appear in block")
    }
}
