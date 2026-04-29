# Phase 100a — AgenticEngine Role Slot Routing Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 99b complete: DomainRegistry, DomainPlugin, MCPDomainAdapter, SoftwareDomain, VerificationBackend all in place.

New surface introduced in phase 100b:
  - `AgentSlot` enum — `execute`, `reason`, `orchestrate`, `vision`
  - `AgenticEngine` replaces `proProvider`/`flashProvider` with slot-keyed providers
  - `AgenticEngine.init(slots:visionProvider:toolRouter:contextManager:)` — new init signature
  - `AgenticEngine.provider(for slot:)` — returns the provider assigned to a slot
  - `AgenticEngine.selectSlot(for message:)` — deterministic slot selection (replaces selectProvider)
  - `system_prompt_addendum` injected per-provider in `buildSystemPrompt()`
  - `AppSettings` gains `slotAssignments: [AgentSlot: String]` (slot → provider ID)

TDD coverage:
  File 1 — AgenticEngineSlotTests: slot assignment, selectSlot routing (vision, execute, reason defaults)

---

## Write to: MerlinTests/Unit/AgenticEngineSlotTests.swift

```swift
import XCTest
@testable import Merlin

final class AgenticEngineSlotTests: XCTestCase {

    private func makeEngine(
        executeID: String = "fast-local",
        reasonID: String = "deep-remote",
        orchestrateID: String? = nil,
        visionID: String = "vision-model"
    ) -> AgenticEngine {
        let registry = ProviderRegistry()
        registry.add(MockProvider(id: "fast-local"))
        registry.add(MockProvider(id: "deep-remote"))
        registry.add(MockProvider(id: "vision-model"))
        if let oid = orchestrateID { registry.add(MockProvider(id: oid)) }

        var slots: [AgentSlot: String] = [
            .execute: executeID,
            .reason: reasonID,
            .vision: visionID,
        ]
        if let oid = orchestrateID { slots[.orchestrate] = oid }

        return AgenticEngine(
            slotAssignments: slots,
            registry: registry,
            toolRouter: ToolRouter(),
            contextManager: ContextManager()
        )
    }

    // MARK: - Slot assignment

    func testProviderForExecuteSlot() {
        let engine = makeEngine()
        let provider = engine.provider(for: .execute)
        XCTAssertEqual(provider?.id, "fast-local")
    }

    func testProviderForReasonSlot() {
        let engine = makeEngine()
        let provider = engine.provider(for: .reason)
        XCTAssertEqual(provider?.id, "deep-remote")
    }

    func testProviderForVisionSlot() {
        let engine = makeEngine()
        let provider = engine.provider(for: .vision)
        XCTAssertEqual(provider?.id, "vision-model")
    }

    func testProviderForOrchestrateFallsBackToReasonWhenUnassigned() {
        let engine = makeEngine(orchestrateID: nil)
        // When orchestrate has no explicit assignment, falls back to reason slot
        let provider = engine.provider(for: .orchestrate)
        XCTAssertEqual(provider?.id, "deep-remote")
    }

    func testProviderForOrchestrateWhenAssigned() {
        let engine = makeEngine(orchestrateID: "orchestrate-model")
        let provider = engine.provider(for: .orchestrate)
        XCTAssertEqual(provider?.id, "orchestrate-model")
    }

    // MARK: - Slot selection

    func testSelectSlotForVisionKeywords() {
        let engine = makeEngine()
        let slot = engine.selectSlot(for: "take a screenshot of the window")
        XCTAssertEqual(slot, .vision)
    }

    func testSelectSlotDefaultsToExecute() {
        let engine = makeEngine()
        let slot = engine.selectSlot(for: "refactor this function to use async/await")
        XCTAssertEqual(slot, .execute)
    }

    func testSelectSlotReasonOverrideAnnotation() {
        let engine = makeEngine()
        let slot = engine.selectSlot(for: "@reason review this migration for correctness")
        XCTAssertEqual(slot, .reason)
    }

    func testSelectSlotOrchestrateAnnotation() {
        let engine = makeEngine()
        let slot = engine.selectSlot(for: "@orchestrate plan the refactor of the auth module")
        XCTAssertEqual(slot, .orchestrate)
    }
}

// MARK: - Helpers

private final class MockProvider: LLMProvider {
    let id: String
    init(id: String) { self.id = id }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { $0.finish() }
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
Expected: BUILD FAILED — `AgentSlot`, `AgenticEngine.init(slotAssignments:registry:toolRouter:contextManager:)`, `AgenticEngine.provider(for:)`, `AgenticEngine.selectSlot(for:)` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AgenticEngineSlotTests.swift
git commit -m "Phase 100a — AgenticEngineSlotTests (failing)"
```
