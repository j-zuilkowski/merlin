# Phase 80a — DisabledSkillNames Enforcement Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 79b complete: SubagentBlockView wired into ChatView.

New surface introduced in phase 80b:
  - `SkillsRegistry.enabledSkills(disabledNames:)` — returns skills not in the disabled list
  - `ContextManager.buildSkillReinjectionBlock(skills:)` — accepts `[Skill]`, filters respected
  - `AgenticEngine` passes `AppSettings.shared.disabledSkillNames` when building skill blocks

TDD coverage:
  File 1 — DisabledSkillsTests: disabled skill excluded from enabledSkills,
            enabled skill included, empty disabled list returns all skills,
            ContextManager injection block omits disabled skill name

---

## Write to: MerlinTests/Unit/DisabledSkillsTests.swift

```swift
import XCTest
@testable import Merlin

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

Expected: `BUILD FAILED` — `enabledSkills(from:disabledNames:)` and
`buildSkillReinjectionBlock(skills:disabledNames:)` not yet present.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/DisabledSkillsTests.swift
git commit -m "Phase 80a — DisabledSkillsTests (failing)"
```
