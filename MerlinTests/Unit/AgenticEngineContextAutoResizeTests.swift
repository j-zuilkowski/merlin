import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineContextAutoResizeTests: XCTestCase {

    func testEngineUsesReturnedModelIDAfterContextResize() async {
        let config = ProviderConfig(
            id: "ollama",
            displayName: "Ollama",
            baseURL: "http://localhost:11434/v1",
            model: "qwen3-coder",
            isEnabled: true,
            isLocal: true,
            supportsThinking: false,
            supportsVision: false,
            kind: .openAICompatible
        )
        let registry = ProviderRegistry(
            persistURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"),
            initialProviders: [config]
        )
        let provider = ResizeCapturingProvider(id: "ollama:qwen3-coder")
        registry.add(provider)
        registry.activeProviderID = "ollama"

        let memory = AuthMemory(storePath: "/tmp/auth-agenticengine-context-auto-resize-tests.json")
        let gate = AuthGate(memory: memory, presenter: TestAuthPresenter())
        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id, .reason: provider.id, .vision: provider.id],
            registry: registry,
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager()
        )
        engine.localModelManagers["ollama"] = ResizeReturningManager(returnedModelID: "qwen3-coder-merlin")

        for await _ in engine.send(userMessage: "hello") {}

        XCTAssertEqual(provider.capturedModels.last, "qwen3-coder-merlin")
        XCTAssertEqual(registry.config(for: "ollama")?.model, "qwen3-coder-merlin")
    }

    func testEngineEnsuresRuntimeModelLoadedBeforeProviderRequest() async {
        let config = ProviderConfig(
            id: "ollama",
            displayName: "Ollama",
            baseURL: "http://localhost:11434/v1",
            model: "qwen3-coder",
            isEnabled: true,
            isLocal: true,
            supportsThinking: false,
            supportsVision: false,
            kind: .openAICompatible
        )
        let registry = ProviderRegistry(
            persistURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"),
            initialProviders: [config]
        )
        let provider = ResizeCapturingProvider(id: "ollama:qwen3-coder")
        registry.add(provider)
        registry.activeProviderID = "ollama"

        let memory = AuthMemory(storePath: "/tmp/auth-agenticengine-runtime-load-tests.json")
        let gate = AuthGate(memory: memory, presenter: TestAuthPresenter())
        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id, .reason: provider.id, .vision: provider.id],
            registry: registry,
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager()
        )
        let manager = RuntimeLoadingManager()
        engine.localModelManagers["ollama"] = manager

        for await _ in engine.send(userMessage: "hello") {}

        XCTAssertEqual(manager.loadedModelIDs, ["qwen3-coder"])
    }
}

private final class ResizeReturningManager: @unchecked Sendable, LocalModelManagerProtocol {
    nonisolated let providerID = "ollama"
    nonisolated let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength]
    )

    private let returnedModelID: String

    init(returnedModelID: String) {
        self.returnedModelID = returnedModelID
    }

    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    nonisolated func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws -> String {
        returnedModelID
    }
}

private final class RuntimeLoadingManager: @unchecked Sendable, LocalModelManagerProtocol {
    nonisolated let providerID = "ollama"
    nonisolated let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength],
        supportsRuntimeModelLoad: true
    )

    private let lock = NSLock()
    private var loadedStorage: [String] = []

    var loadedModelIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return loadedStorage
    }

    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    nonisolated func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws -> String {
        modelID
    }
    func ensureModelLoaded(modelID: String) async throws {
        lock.lock()
        loadedStorage.append(modelID)
        lock.unlock()
    }
}

private final class ResizeCapturingProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    nonisolated(unsafe) var capturedModels: [String] = []

    init(id: String) {
        self.id = id
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        capturedModels.append(request.model)
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(delta: .init(content: "ok"), finishReason: "stop"))
            continuation.finish()
        }
    }
}

@MainActor
private final class TestAuthPresenter: AuthPresenter {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        .allow
    }
}
