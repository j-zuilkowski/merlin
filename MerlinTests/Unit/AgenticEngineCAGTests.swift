import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineCAGTests: XCTestCase {

    private func makeEngine(provider: any LLMProvider) -> AgenticEngine {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-cag-tests-\(UUID().uuidString).json"),
            initialProviders: [
                ProviderConfig(
                    id: provider.id,
                    displayName: provider.id,
                    baseURL: provider.baseURL.absoluteString,
                    model: "",
                    isEnabled: true,
                    isLocal: true,
                    supportsThinking: false,
                    supportsVision: false,
                    kind: .openAICompatible
                )
            ]
        )
        registry.add(provider)
        registry.activeProviderID = provider.id
        return AgenticEngine(
            slotAssignments: [.execute: provider.id, .reason: provider.id, .vision: provider.id],
            registry: registry,
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager()
        )
    }

    override func tearDown() {
        AppSettings.shared.cagEnabled = false
        super.tearDown()
    }

    func testEngineMarksRequestsEphemeralWhenCAGEnabled() async {
        let provider = CAGCapturingProvider()
        let engine = makeEngine(provider: provider)
        AppSettings.shared.cagEnabled = true

        for await _ in engine.send(userMessage: "hello") {}

        XCTAssertEqual(provider.lastRequest?.cachePolicy, .ephemeral)
    }

    func testEngineLeavesRequestsUncachedWhenCAGDisabled() async {
        let provider = CAGCapturingProvider()
        let engine = makeEngine(provider: provider)
        AppSettings.shared.cagEnabled = false

        for await _ in engine.send(userMessage: "hello") {}

        XCTAssertEqual(provider.lastRequest?.cachePolicy, .disabled)
    }

    func testOfferedToolsAreSortedBeforeProviderRequest() async {
        let provider = CAGCapturingProvider()
        let engine = makeEngine(provider: provider)

        for await _ in engine.send(userMessage: "hello") {}

        let toolNames = provider.lastRequest?.tools?.map(\.function.name) ?? []
        XCTAssertEqual(toolNames, toolNames.sorted())
    }
}

private final class CAGCapturingProvider: LLMProvider {
    let id: String = "cag-capture"
    let baseURL: URL = URL(string: "http://localhost:9999/v1")!
    private(set) var lastRequest: CompletionRequest?

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        lastRequest = request
        return AsyncThrowingStream { continuation in
            continuation.yield(.init(delta: .init(content: "ok"), finishReason: nil))
            continuation.yield(.init(delta: nil, finishReason: "stop"))
            continuation.finish()
        }
    }
}
