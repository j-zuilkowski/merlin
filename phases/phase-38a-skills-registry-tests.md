# Phase 38a — SkillsRegistry Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 37b complete: ContextInjector (@mention, attachment, drag-drop).

New surface introduced in phase 38b:
  - `SkillFrontmatter` — Codable struct from YAML frontmatter: name, description,
    argumentHint, model, userInvocable, disableModelInvocation, allowedTools, context
  - `Skill` — struct: name (String), frontmatter (SkillFrontmatter), body (String),
    directory (URL)
  - `SkillsRegistry` — @MainActor ObservableObject: loads skills from personal
    (~/.merlin/skills/) and project (.merlin/skills/) directories; watches for live
    changes via FSEvents; exposes `skills: [Skill]`; `skill(named:) -> Skill?`
  - `SkillsRegistry.render(skill:arguments:) -> String` — expands $ARGUMENTS and
    shell-injection backtick blocks in skill body

TDD coverage:
  File 1 — SkillsRegistryTests: load from directory; priority (project > personal);
            skill(named:) lookup; render substitutes $ARGUMENTS; missing dir returns empty

---

## Write to: MerlinTests/Unit/SkillsRegistryTests.swift

```swift
import XCTest
@testable import Merlin

final class SkillsRegistryTests: XCTestCase {

    private var personalDir: URL!
    private var projectDir: URL!

    override func setUp() {
        super.setUp()
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skills-test-\(UUID().uuidString)")
        personalDir = base.appendingPathComponent("personal")
        projectDir  = base.appendingPathComponent("project")
        try! FileManager.default.createDirectory(at: personalDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: projectDir,  withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: personalDir.deletingLastPathComponent())
        super.tearDown()
    }

    // MARK: - Loading

    func testLoadsSkillFromPersonalDirectory() throws {
        try writeSkill(name: "review", body: "Review the code.", in: personalDir)
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: nil)
        registry.reload()
        XCTAssertNotNil(registry.skill(named: "review"))
    }

    func testLoadsSkillFromProjectDirectory() throws {
        try writeSkill(name: "deploy", body: "Deploy the app.", in: projectDir)
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: projectDir)
        registry.reload()
        XCTAssertNotNil(registry.skill(named: "deploy"))
    }

    func testEmptyDirectoryReturnsNoSkills() {
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: nil)
        registry.reload()
        XCTAssertTrue(registry.skills.isEmpty)
    }

    func testMissingPersonalDirDoesNotCrash() {
        let missing = URL(fileURLWithPath: "/nonexistent/path/skills")
        let registry = SkillsRegistry(personalDir: missing, projectDir: nil)
        registry.reload()
        XCTAssertTrue(registry.skills.isEmpty)
    }

    // MARK: - Priority

    func testProjectSkillOverridesPersonalSkillWithSameName() throws {
        try writeSkill(name: "test", body: "personal body", in: personalDir)
        try writeSkill(name: "test", body: "project body", in: projectDir)
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: projectDir)
        registry.reload()
        let skill = registry.skill(named: "test")
        XCTAssertEqual(skill?.body, "project body",
                       "Project skill must take priority over personal skill with same name")
    }

    // MARK: - Frontmatter parsing

    func testFrontmatterDescriptionIsParsed() throws {
        let md = """
        ---
        name: review
        description: Review staged changes for quality issues
        ---

        Look at the diff and give feedback.
        """
        try writeSkillContent(name: "review", content: md, in: personalDir)
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: nil)
        registry.reload()
        let skill = registry.skill(named: "review")
        XCTAssertEqual(skill?.frontmatter.description, "Review staged changes for quality issues")
    }

    func testSkillBodyExcludesFrontmatter() throws {
        let md = """
        ---
        name: explain
        ---

        Explain the code clearly.
        """
        try writeSkillContent(name: "explain", content: md, in: personalDir)
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: nil)
        registry.reload()
        let skill = registry.skill(named: "explain")
        XCTAssertFalse(skill?.body.contains("---") ?? true,
                       "Skill body must not contain frontmatter delimiters")
        XCTAssertTrue(skill?.body.contains("Explain the code clearly.") ?? false)
    }

    // MARK: - render

    func testRenderSubstitutesArgumentsToken() throws {
        let md = "Refactor this: $ARGUMENTS"
        try writeSkill(name: "refactor", body: md, in: personalDir)
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: nil)
        registry.reload()
        let skill = registry.skill(named: "refactor")!
        let rendered = registry.render(skill: skill, arguments: "MyClass.swift")
        XCTAssertEqual(rendered, "Refactor this: MyClass.swift")
    }

    func testRenderAppendsArgumentsWhenTokenAbsent() throws {
        let md = "Review the staged changes."
        try writeSkill(name: "review", body: md, in: personalDir)
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: nil)
        registry.reload()
        let skill = registry.skill(named: "review")!
        let rendered = registry.render(skill: skill, arguments: "extra context")
        XCTAssertTrue(rendered.contains("Review the staged changes."))
        XCTAssertTrue(rendered.contains("extra context"),
                      "Arguments must be appended when $ARGUMENTS is absent")
    }

    func testRenderWithNoArgumentsDoesNotAppendBlank() throws {
        let md = "Do the thing."
        try writeSkill(name: "thing", body: md, in: personalDir)
        let registry = SkillsRegistry(personalDir: personalDir, projectDir: nil)
        registry.reload()
        let skill = registry.skill(named: "thing")!
        let rendered = registry.render(skill: skill, arguments: "")
        XCTAssertEqual(rendered.trimmingCharacters(in: .whitespacesAndNewlines), "Do the thing.")
    }

    // MARK: - Helpers

    private func writeSkill(name: String, body: String, in dir: URL) throws {
        try writeSkillContent(name: name, content: body, in: dir)
    }

    private func writeSkillContent(name: String, content: String, in dir: URL) throws {
        let skillDir = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"),
                          atomically: true, encoding: .utf8)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `SkillsRegistry`, `Skill`, `SkillFrontmatter`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SkillsRegistryTests.swift
git commit -m "Phase 38a — SkillsRegistryTests (failing)"
```
