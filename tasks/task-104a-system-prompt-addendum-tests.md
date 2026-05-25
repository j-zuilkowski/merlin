# Phase 104a — System Prompt Addendum Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 103b complete: PlannerEngine in place.

New surface introduced in phase 104:
  - `ProviderConfig.systemPromptAddendum: String` — per-provider text appended to system prompt
  - `AgenticEngine.buildSystemPrompt(for:)` — slot-aware variant that injects provider + domain addenda
  - `AgenticEngine.currentAddendumHash(for:)` — SHA256 prefix of the combined addendum for tracking
  - `String.addendumHash` — convenience computed property returning 8-char SHA256 hex prefix

TDD coverage:
  File 1 — SystemPromptAddendumTests: addendum injection, hash computation, empty-addendum guard,
            slot-aware lookup, domain addendum ordering

---

## Write to: MerlinTests/Unit/SystemPromptAddendumTests.swift

```swift
import XCTest
@testable import Merlin

final class SystemPromptAddendumTests: XCTestCase {

    // MARK: - String.addendumHash

    func testAddendumHashIsEightChars() {
        let hash = "some addendum text".addendumHash
        XCTAssertEqual(hash.count, 8)
    }

    func testAddendumHashIsConsistent() {
        let text = "Always produce complete code blocks."
        XCTAssertEqual(text.addendumHash, text.addendumHash)
    }

    func testAddendumHashDiffersForDifferentStrings() {
        let a = "Always produce complete code blocks.".addendumHash
        let b = "Think through each step before writing code.".addendumHash
        XCTAssertNotEqual(a, b)
    }

    func testEmptyStringHashIsStable() {
        // Empty addendum still hashes (to a constant sentinel value — "00000000")
        XCTAssertEqual("".addendumHash, "00000000")
    }

    // MARK: - Provider addendum injection

    func testProviderAddendumAppearsInSystemPrompt() async {
        let engine = makeEngineWithAddendum("Always produce complete code blocks.", slot: .execute)
        let prompt = await engine.buildSystemPromptForTesting(slot: .execute)
        XCTAssertTrue(
            prompt.contains("Always produce complete code blocks."),
            "Provider addendum must appear in system prompt for its assigned slot"
        )
    }

    func testEmptyProviderAddendumDoesNotAddExtraSection() async {
        let engine = makeEngineWithAddendum("", slot: .execute)
        let prompt = await engine.buildSystemPromptForTesting(slot: .execute)
        // Should have exactly one trailing newline separator — the base "You are Merlin…" is last
        let sectionCount = prompt.components(separatedBy: "\n\n").filter { !$0.isEmpty }.count
        let baseline = makeEngineWithAddendum(nil, slot: .execute)
        let baselinePrompt = await baseline.buildSystemPromptForTesting(slot: .execute)
        let baselineCount = baselinePrompt.components(separatedBy: "\n\n").filter { !$0.isEmpty }.count
        XCTAssertEqual(sectionCount, baselineCount, "Empty addendum must not add an extra section")
    }

    func testAddendumOnlyAppearsForAssignedSlot() async {
        // Execute slot has addendum; reason slot does not
        let engine = makeEngineWithAddendum("Execute-only addendum.", slot: .execute)
        let reasonPrompt = await engine.buildSystemPromptForTesting(slot: .reason)
        XCTAssertFalse(
            reasonPrompt.contains("Execute-only addendum."),
            "Addendum for execute slot must not bleed into reason slot"
        )
    }

    // MARK: - currentAddendumHash

    func testCurrentAddendumHashMatchesProviderAddendum() async {
        let addendum = "Think through each step."
        let engine = makeEngineWithAddendum(addendum, slot: .execute)
        let hash = await engine.currentAddendumHash(for: .execute)
        XCTAssertEqual(hash, addendum.addendumHash)
    }

    func testCurrentAddendumHashIsZeroesWhenNoAddendum() async {
        let engine = makeEngineWithAddendum(nil, slot: .execute)
        let hash = await engine.currentAddendumHash(for: .execute)
        XCTAssertEqual(hash, "00000000")
    }
}

// MARK: - Helpers

/// Builds an AgenticEngine whose execute (or specified) slot is backed by a provider
/// whose `systemPromptAddendum` is `addendum` (nil = no addendum / use default "").
private func makeEngineWithAddendum(
    _ addendum: String?,
    slot: AgentSlot
) -> AgenticEngine {
    let providerID = "addendum-provider"
    var config = ProviderConfig(id: providerID, baseURL: "http://localhost", modelName: "test")
    config.systemPromptAddendum = addendum ?? ""

    let registry = ProviderRegistry()
    let provider = ScriptedProviderA(id: providerID)
    registry.add(provider, config: config)

    let slots: [AgentSlot: String] = [slot: providerID]
    return AgenticEngine(
        slotAssignments: slots,
        registry: registry,
        toolRouter: ToolRouter(),
        contextManager: ContextManager()
    )
}

private final class ScriptedProviderA: LLMProvider {
    let id: String
    init(id: String) { self.id = id }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: "ok", thinkingContent: nil, toolCalls: nil), finishReason: "stop"))
            c.finish()
        }
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
Expected: BUILD FAILED — `ProviderConfig.systemPromptAddendum`, `String.addendumHash`,
`AgenticEngine.buildSystemPromptForTesting(slot:)`, and `AgenticEngine.currentAddendumHash(for:)` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SystemPromptAddendumTests.swift
git commit -m "Phase 104a — SystemPromptAddendumTests (failing)"
```
