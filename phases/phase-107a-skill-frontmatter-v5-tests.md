# Phase 107a — V5 Skill Frontmatter Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 106 complete: V5 Settings UI in place.

New surface introduced in phase 107b:
  - `SkillFrontmatter` gains `role: AgentSlot?` and `complexity: ComplexityTier?` keys
  - `AgenticEngine.invokeSkill(_:arguments:)` respects frontmatter role and complexity overrides
  - Skill with `role: reason` always routes to reason slot
  - Skill with `complexity: high-stakes` always uses high-stakes routing regardless of classifier

TDD coverage:
  File 1 — SkillFrontmatterV5Tests: parse role key, parse complexity key, invokeSkill uses declared slot, invokeSkill uses declared complexity

---

## Write to: MerlinTests/Unit/SkillFrontmatterV5Tests.swift

```swift
import XCTest
@testable import Merlin

final class SkillFrontmatterV5Tests: XCTestCase {

    // MARK: - Frontmatter parsing

    func testParseRoleKey() throws {
        let md = """
        ---
        name: security-review
        description: Review for security issues
        role: reason
        ---
        Review the following for security vulnerabilities.
        """
        let skill = try SkillsRegistry.parseSkill(markdown: md)
        XCTAssertEqual(skill.frontmatter.role, .reason)
    }

    func testParseComplexityKey() throws {
        let md = """
        ---
        name: migrate-schema
        description: Run DB migration
        complexity: high-stakes
        ---
        Apply the migration carefully.
        """
        let skill = try SkillsRegistry.parseSkill(markdown: md)
        XCTAssertEqual(skill.frontmatter.complexity, .highStakes)
    }

    func testNilRoleWhenNotDeclared() throws {
        let md = """
        ---
        name: summarise
        description: Summarise content
        ---
        Summarise this.
        """
        let skill = try SkillsRegistry.parseSkill(markdown: md)
        XCTAssertNil(skill.frontmatter.role)
    }

    func testNilComplexityWhenNotDeclared() throws {
        let md = """
        ---
        name: summarise
        description: Summarise content
        ---
        Summarise this.
        """
        let skill = try SkillsRegistry.parseSkill(markdown: md)
        XCTAssertNil(skill.frontmatter.complexity)
    }

    // MARK: - invokeSkill routing

    func testInvokeSkillWithReasonRoleUsesReasonSlot() async {
        let providerSpy = ProviderCallSpy()
        let engine = makeEngine(reasonProvider: providerSpy)

        var frontmatter = SkillFrontmatter(name: "test", description: "test")
        frontmatter.role = .reason
        let skill = Skill(frontmatter: frontmatter, body: "Do something important.")

        let events = await collectEvents(engine.invokeSkill(skill))
        XCTAssertTrue(providerSpy.wasCalled, "Skill with role: reason should use the reason slot provider")
    }

    func testInvokeSkillWithHighStakesComplexityRunsCritic() async {
        let criticSpy = CriticSpy()
        let engine = makeEngine()
        engine.criticOverride = criticSpy

        var frontmatter = SkillFrontmatter(name: "test", description: "test")
        frontmatter.complexity = .highStakes
        let skill = Skill(frontmatter: frontmatter, body: "High-stakes skill.")

        _ = await collectEvents(engine.invokeSkill(skill))
        XCTAssertTrue(criticSpy.wasEvaluated, "Skill with complexity: high-stakes should run the critic")
    }
}

// MARK: - Helpers

private func collectEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private func makeEngine(reasonProvider: (any LLMProvider)? = nil) -> AgenticEngine {
    let registry = ProviderRegistry()
    let execute = ScriptedProvider(id: "execute", response: "done")
    registry.add(execute)
    var slots: [AgentSlot: String] = [.execute: "execute"]
    if let rp = reasonProvider {
        registry.add(rp)
        slots[.reason] = rp.id
    }
    return AgenticEngine(
        slotAssignments: slots,
        registry: registry,
        toolRouter: ToolRouter(),
        contextManager: ContextManager()
    )
}

private final class ScriptedProvider: LLMProvider {
    let id: String
    var response: String
    init(id: String, response: String) { self.id = id; self.response = response }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: text, thinkingContent: nil, toolCalls: nil), finishReason: "stop"))
            c.finish()
        }
    }
}

private final class ProviderCallSpy: LLMProvider {
    let id = "spy-reason"
    var wasCalled = false
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        wasCalled = true
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: "done", thinkingContent: nil, toolCalls: nil), finishReason: "stop"))
            c.finish()
        }
    }
}

private final class CriticSpy: CriticEngineProtocol {
    var wasEvaluated = false
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        wasEvaluated = true
        return .pass
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
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `SkillFrontmatter.role`, `SkillFrontmatter.complexity` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SkillFrontmatterV5Tests.swift
git commit -m "Phase 107a — SkillFrontmatterV5Tests (failing)"
```
