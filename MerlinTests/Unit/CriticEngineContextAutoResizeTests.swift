import XCTest
@testable import Merlin

final class CriticEngineContextAutoResizeTests: XCTestCase {

    private let taskType = DomainTaskType(
        domainID: "software", name: "document", displayName: "Document"
    )

    func testCriticCallsEnsureContextLengthBeforeStage2() async {
        let spy = CtxResizeSpy()
        let provider = CtxCapturingProvider(id: "lmstudio:qwen/qwen3.6-27b", response: "PASS: ok")
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            modelManager: spy
        )
        _ = await engine.evaluate(
            taskType: taskType, output: "Some output to verify.",
            context: [], writtenFiles: []
        )
        XCTAssertTrue(spy.ensureCalled, "CriticEngine must call ensureContextLength before Stage 2")
        XCTAssertEqual(spy.capturedModelID, "qwen/qwen3.6-27b",
                       "Model ID must be the resolved (non-prefixed) ID")
    }

    func testCriticProceedsEvenIfEnsureContextLengthThrows() async {
        let failManager = CtxResizeFailingManager()
        let provider = CtxCapturingProvider(id: "lmstudio:qwen/qwen3.6-27b", response: "PASS: ok")
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            modelManager: failManager
        )
        let result = await engine.evaluate(
            taskType: taskType, output: "output text",
            context: [], writtenFiles: []
        )
        XCTAssertEqual(result, CriticResult.pass,
                       "Critic must proceed to Stage 2 even when ensureContextLength throws")
    }

    func testEstimatedTokensIncludePromptOverhead() async {
        let spy = CtxResizeSpy()
        let output = String(repeating: "w", count: 4000)
        let provider = CtxCapturingProvider(id: "lmstudio:qwen/qwen3.6-27b", response: "PASS: ok")
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            modelManager: spy
        )
        _ = await engine.evaluate(
            taskType: taskType, output: output,
            context: [], writtenFiles: []
        )
        XCTAssertGreaterThan(spy.capturedMinimumTokens ?? 0, 512,
                             "Estimated tokens must include prompt overhead")
    }
}

private final class CtxResizeSpy: @unchecked Sendable, LocalModelManagerProtocol {
    nonisolated let providerID = "lmstudio"
    nonisolated let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true, supportedLoadParams: [.contextLength]
    )
    nonisolated(unsafe) var ensureCalled = false
    nonisolated(unsafe) var capturedModelID: String?
    nonisolated(unsafe) var capturedMinimumTokens: Int?

    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    nonisolated func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws {
        ensureCalled = true
        capturedModelID = modelID
        capturedMinimumTokens = minimumTokens
    }
}

private final class CtxResizeFailingManager: @unchecked Sendable, LocalModelManagerProtocol {
    nonisolated let providerID = "lmstudio"
    nonisolated let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true, supportedLoadParams: [.contextLength]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    nonisolated func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws {
        throw ModelManagerError.providerUnavailable
    }
}

private final class CtxCapturingProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let response: String
    init(id: String, response: String) { self.id = id; self.response = response }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: text, toolCalls: nil, thinkingContent: nil),
                finishReason: "stop"
            ))
            c.finish()
        }
    }
}
