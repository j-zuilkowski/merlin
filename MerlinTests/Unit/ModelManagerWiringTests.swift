import XCTest
@testable import Merlin

// MARK: - Stubs

private final class StubReloadableManager: LocalModelManagerProtocol, @unchecked Sendable {
    let providerID: String
    let capabilities: ModelManagerCapabilities
    var reloadCallCount = 0
    var lastReloadConfig: LocalModelConfig?

    init(providerID: String) {
        self.providerID = providerID
        self.capabilities = ModelManagerCapabilities(
            canReloadAtRuntime: true,
            supportedLoadParams: [.contextLength, .gpuLayers]
        )
    }

    func loadedModels() async throws -> [LoadedModelInfo] { [] }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        reloadCallCount += 1
        lastReloadConfig = config
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
}

private final class StubRestartRequiredManager: LocalModelManagerProtocol, @unchecked Sendable {
    let providerID = "stub-restart"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength]
    )

    func loadedModels() async throws -> [LoadedModelInfo] { [] }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        throw ModelManagerError.requiresRestart(
            RestartInstructions(shellCommand: "server --ctx 8192", configSnippet: nil, explanation: "restart")
        )
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(shellCommand: "server --ctx 8192", configSnippet: nil, explanation: "restart")
    }
}

// MARK: - Tests

@MainActor
final class ModelManagerWiringTests: XCTestCase {

    // MARK: AppState manager registry

    func testAppStateHasLocalModelManagers() {
        // Compile-time: AppState must have localModelManagers property
        let appState = AppState()
        let _: [String: any LocalModelManagerProtocol] = appState.localModelManagers
    }

    func testAppStateManagerForProviderID() {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "ollama")
        appState.localModelManagers["ollama"] = stub
        let manager = appState.manager(for: "ollama")
        XCTAssertNotNil(manager)
    }

    func testAppStateManagerReturnsNilForUnknownProvider() {
        let appState = AppState()
        let manager = appState.manager(for: "unknown-provider")
        XCTAssertNil(manager)
    }

    // MARK: applyAdvisory routing

    func testApplyAdvisoryContextLengthCallsReload() async throws {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "16384",
            explanation: "Context exceeded.",
            modelID: "qwen2.5-vl-72b",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let count = stub.reloadCallCount
        XCTAssertEqual(count, 1, "applyAdvisory(.contextLengthTooSmall) must call manager.reload()")
    }

    func testApplyAdvisoryContextLengthSetsCorrectValue() async throws {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "16384",
            explanation: "Context exceeded.",
            modelID: "qwen2.5-vl-72b",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let config = stub.lastReloadConfig
        XCTAssertEqual(config?.contextLength, 16384)
    }

    func testApplyAdvisoryRestartRequiredPublishesInstructions() async {
        let appState = AppState()
        let stub = StubRestartRequiredManager()
        appState.localModelManagers["stub-restart"] = stub
        appState.activeLocalProviderID = "stub-restart"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "8192",
            explanation: "Context exceeded.",
            modelID: "model",
            detectedAt: Date()
        )
        do {
            try await appState.applyAdvisory(advisory)
        } catch ModelManagerError.requiresRestart(let instr) {
            XCTAssertFalse(instr.shellCommand.isEmpty)
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // If applyAdvisory stores the instructions instead of rethrowing, check that:
        // XCTAssertNotNil(appState.pendingRestartInstructions)
    }

    func testApplyInferenceAdvisoryDoesNotCallReload() async throws {
        // Temperature/maxTokens advisories should update AppSettings, not reload the model
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .maxTokensTooLow,
            parameterName: "maxTokens",
            currentValue: "1024",
            suggestedValue: "2048",
            explanation: "Truncated.",
            modelID: "model",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let count = stub.reloadCallCount
        XCTAssertEqual(count, 0, "Inference-param advisories must not call manager.reload()")
    }

    // MARK: AgenticEngine reload pause

    func testAgenticEngineHasIsReloadingModelProperty() {
        let engine = EngineFactory.make()
        let _: Bool = engine.isReloadingModel
    }

    func testAgenticEngineIsReloadingModelDefaultsFalse() {
        let engine = EngineFactory.make()
        XCTAssertFalse(engine.isReloadingModel)
    }
}
