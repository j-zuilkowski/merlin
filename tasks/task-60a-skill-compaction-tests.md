# Phase 60a — Skill Compaction Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 59 complete: V4 subagent sidebar UI.

New surface introduced in phase 60b:
  - `ContextManager.recordSkillInvocation(_ skill: Skill)` — prepends to recent list, max 20
  - `ContextManager.recentlyInvokedSkills: [Skill]` — most-recent first
  - `ContextManager.compact()` — after compaction, appends a system message re-injecting up to
    25,000 estimated tokens of most-recently-invoked skills (5,000 token budget per skill)

TDD coverage:
  File 1 — SkillCompactionTests: record/order/cap, re-injection after compaction, token budget

---

## Write to: MerlinTests/Unit/SkillCompactionTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SkillCompactionTests: XCTestCase {

    // MARK: - Helpers

    private func makeSkill(name: String, body: String) -> Skill {
        Skill(
            name: name,
            frontmatter: SkillFrontmatter(),
            body: body,
            directory: URL(fileURLWithPath: "/tmp"),
            isProjectScoped: false
        )
    }

    private func makeManager() -> ContextManager {
        ContextManager()
    }

    // MARK: - Recording

    func testRecordSkillAddsToRecentList() {
        let ctx = makeManager()
        let skill = makeSkill(name: "review", body: "## Review\nCheck the diff.")
        ctx.recordSkillInvocation(skill)
        XCTAssertEqual(ctx.recentlyInvokedSkills.count, 1)
        XCTAssertEqual(ctx.recentlyInvokedSkills[0].name, "review")
    }

    func testRecordSkillPrependsNewestFirst() {
        let ctx = makeManager()
        ctx.recordSkillInvocation(makeSkill(name: "first", body: "first"))
        ctx.recordSkillInvocation(makeSkill(name: "second", body: "second"))
        XCTAssertEqual(ctx.recentlyInvokedSkills[0].name, "second")
        XCTAssertEqual(ctx.recentlyInvokedSkills[1].name, "first")
    }

    func testRecordSkillCapAt20() {
        let ctx = makeManager()
        for i in 0..<25 {
            ctx.recordSkillInvocation(makeSkill(name: "skill_\(i)", body: "body"))
        }
        XCTAssertEqual(ctx.recentlyInvokedSkills.count, 20)
        XCTAssertEqual(ctx.recentlyInvokedSkills[0].name, "skill_24")
    }

    func testRecordSameSkillMovesItToFront() {
        let ctx = makeManager()
        ctx.recordSkillInvocation(makeSkill(name: "review", body: "body"))
        ctx.recordSkillInvocation(makeSkill(name: "test", body: "body"))
        ctx.recordSkillInvocation(makeSkill(name: "review", body: "body"))
        XCTAssertEqual(ctx.recentlyInvokedSkills[0].name, "review")
        XCTAssertEqual(ctx.recentlyInvokedSkills.filter { $0.name == "review" }.count, 1)
    }

    // MARK: - Re-injection after compaction

    func testCompactionInjectsSkillBlock() {
        let ctx = makeManager()
        ctx.recordSkillInvocation(makeSkill(name: "review", body: "Check the staged diff carefully."))

        // Add enough tool messages to trigger old-tool compaction
        for i in 0..<25 {
            ctx.append(Message(role: .tool, content: .text("result \(i)"), toolCallId: "id\(i)", timestamp: Date()))
        }
        ctx.forceCompaction()

        let systemMessages = ctx.messages.filter {
            if case .text(let t) = $0.content { return $0.role == .system && t.contains("[Skills]") }
            return false
        }
        XCTAssertFalse(systemMessages.isEmpty, "Expected a [Skills] re-injection system message after compaction")
    }

    func testCompactionSkillBlockContainsSkillBody() {
        let ctx = makeManager()
        let body = "## Review\nAlways check for off-by-one errors."
        ctx.recordSkillInvocation(makeSkill(name: "review", body: body))

        ctx.append(Message(role: .tool, content: .text("tool result"), toolCallId: "id1", timestamp: Date()))
        ctx.forceCompaction()

        let allText = ctx.messages.compactMap { msg -> String? in
            if case .text(let t) = msg.content { return t }
            return nil
        }.joined()
        XCTAssertTrue(allText.contains("off-by-one"), "Skill body should appear in messages after compaction")
    }

    func testCompactionRespectsTokenBudget() {
        let ctx = makeManager()
        // Each skill body is ~30,000 chars ≈ 8,500 tokens — 3 skills would exceed 25K budget
        let largeBody = String(repeating: "x", count: 30_000)
        for i in 0..<3 {
            ctx.recordSkillInvocation(makeSkill(name: "skill_\(i)", body: largeBody))
        }
        ctx.append(Message(role: .tool, content: .text("result"), toolCallId: "id1", timestamp: Date()))
        ctx.forceCompaction()

        let skillMessages = ctx.messages.filter {
            if case .text(let t) = $0.content { return t.contains("[Skills]") }
            return false
        }
        // At most 2 skills should be injected (2 × ~8,500 = 17,000 < 25,000; 3rd would exceed)
        if let text = skillMessages.first.flatMap({ msg -> String? in
            if case .text(let t) = msg.content { return t }
            return nil
        }) {
            let injectedCount = (text.components(separatedBy: "## skill_")).count - 1
            XCTAssertLessThanOrEqual(injectedCount, 2, "Token budget should cap injected skills")
        }
    }

    func testNoSkillsNoInjectionBlock() {
        let ctx = makeManager()
        ctx.append(Message(role: .tool, content: .text("result"), toolCallId: "id1", timestamp: Date()))
        ctx.forceCompaction()

        let skillMessages = ctx.messages.filter {
            if case .text(let t) = $0.content { return t.contains("[Skills]") }
            return false
        }
        XCTAssertTrue(skillMessages.isEmpty, "No skills recorded means no injection block")
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

Expected: `BUILD FAILED` with errors referencing `recordSkillInvocation`, `recentlyInvokedSkills`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SkillCompactionTests.swift
git commit -m "Phase 60a — SkillCompactionTests (failing)"
```
