import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineSlotTests: XCTestCase {

    private func makeEngine(
        executeID: String = "fast-local",
        reasonID: String = "deep-remote",
        orchestrateID: String? = nil,
        visionID: String = "vision-model"
    ) -> AgenticEngine {
        let registry = ProviderRegistry()
        registry.add(SlotMockProvider(id: "fast-local"))
        registry.add(SlotMockProvider(id: "deep-remote"))
        registry.add(SlotMockProvider(id: "vision-model"))
        if let oid = orchestrateID { registry.add(SlotMockProvider(id: oid)) }

        let memory = AuthMemory(storePath: "/tmp/auth-agenticengine-slot-tests.json")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())

        var slots: [AgentSlot: String] = [
            .execute: executeID,
            .reason: reasonID,
            .vision: visionID,
        ]
        if let oid = orchestrateID { slots[.orchestrate] = oid }

        return AgenticEngine(
            slotAssignments: slots,
            registry: registry,
            toolRouter: ToolRouter(authGate: gate),
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

    func testSelectSlotLongWorkflowMentioningScreenshotsStaysExecute() {
        let engine = makeEngine()
        let prompt = """
        Design a complete electronics workflow. Generate KiCad files, SPICE simulation, Gerbers,
        a BOM, and a final report with a screenshot/artifact index. Capture screenshots throughout
        the workflow as evidence, but run the design and generation work normally.
        """ + String(repeating: " generate artifact", count: 40)

        let slot = engine.selectSlot(for: prompt)

        XCTAssertEqual(slot, .execute)
    }

    func testSelectSlotVisionOverrideAnnotation() {
        let engine = makeEngine()
        let slot = engine.selectSlot(for: "@vision inspect the screenshot and summarize it")
        XCTAssertEqual(slot, .vision)
    }

    func testSelectSlotDefaultsToExecute() {
        let engine = makeEngine()
        let slot = engine.selectSlot(for: "refactor this function to use async/await")
        XCTAssertEqual(slot, .execute)
    }

    func testSelectSlotCodingPromptWithClickButtonStaysExecute() {
        let engine = makeEngine()
        // A coding/debug task that merely mentions clicking buttons must run on the
        // execute model — routing the whole agentic loop to the smaller vision model
        // cripples it (this mis-routed S1's Swift-GUI-debug scenario).
        let slot = engine.selectSlot(
            for: "Build the app, launch it, and click every toolbar button to find defects")
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

private final class SlotMockProvider: LLMProvider {
    let id: String
    init(id: String) { self.id = id }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
