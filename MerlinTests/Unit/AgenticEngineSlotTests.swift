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
