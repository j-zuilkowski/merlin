import XCTest
@testable import Merlin

@MainActor
final class LoRAProviderRoutingTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func makeEngine(
        proProvider: MockProvider? = nil,
        flashProvider: MockProvider? = nil
    ) -> AgenticEngine {
        let pro = proProvider ?? MockProvider()
        let flash = flashProvider ?? MockProvider()

        let proConfig = ProviderConfig(
            id: pro.id, displayName: pro.id,
            baseURL: pro.baseURL.absoluteString,
            model: "", isEnabled: true, isLocal: true,
            supportsThinking: false, supportsVision: false, kind: .openAICompatible
        )
        let flashConfig = ProviderConfig(
            id: flash.id, displayName: flash.id,
            baseURL: flash.baseURL.absoluteString,
            model: "", isEnabled: true, isLocal: true,
            supportsThinking: false, supportsVision: false, kind: .openAICompatible
        )
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-lora-\(UUID().uuidString).json"),
            initialProviders: [proConfig, flashConfig]
        )
        registry.add(pro)
        registry.add(flash)
        registry.activeProviderID = pro.id

        let memory = AuthMemory(storePath: "/tmp/auth-lora-\(UUID().uuidString).json")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())

        return AgenticEngine(
            slotAssignments: [.execute: pro.id, .reason: flash.id],
            registry: registry,
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager()
        )
    }

    // MARK: - Execute slot returns loraProvider when set

    func testExecuteSlotReturnsLoRAProviderWhenSet() {
        let engine = makeEngine()
        let loraProvider = MockProvider()
        loraProvider.id_ = "lora-local"

        // BUILD FAILED until 120b adds AgenticEngine.loraProvider
        engine.loraProvider = loraProvider

        let resolved = engine.provider(for: .execute)
        XCTAssertTrue((resolved as? MockProvider)?.id == "lora-local",
                      "Execute slot must return loraProvider when it is set")
    }

    // MARK: - Falls back to proProvider when loraProvider is nil

    func testExecuteSlotFallsBackToProProviderWhenLoRANil() {
        let proMock = MockProvider()
        proMock.id_ = "pro"
        let engine = makeEngine(proProvider: proMock)
        engine.loraProvider = nil

        let resolved = engine.provider(for: .execute)
        XCTAssertTrue((resolved as? MockProvider)?.id == "pro",
                      "Execute slot must fall back to proProvider when loraProvider is nil")
    }

    // MARK: - Reason slot always unaffected by loraProvider

    func testReasonSlotAlwaysUsesFlashProvider() {
        let flashMock = MockProvider()
        flashMock.id_ = "flash"
        let engine = makeEngine(flashProvider: flashMock)

        let loraProvider = MockProvider()
        loraProvider.id_ = "lora-local"
        engine.loraProvider = loraProvider

        let resolved = engine.provider(for: .reason)
        XCTAssertTrue((resolved as? MockProvider)?.id == "flash",
                      "Reason slot must always use flashProvider, never loraProvider")
    }

    // MARK: - Clearing loraProvider restores proProvider

    func testClearingLoRAProviderRestoresProProvider() {
        let proMock = MockProvider()
        proMock.id_ = "pro"
        let engine = makeEngine(proProvider: proMock)

        let loraProvider = MockProvider()
        loraProvider.id_ = "lora-local"
        engine.loraProvider = loraProvider

        // Clear it
        engine.loraProvider = nil

        let resolved = engine.provider(for: .execute)
        XCTAssertTrue((resolved as? MockProvider)?.id == "pro",
                      "Clearing loraProvider must restore proProvider for execute slot")
    }
}
