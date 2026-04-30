import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineMemoryPluginTests: XCTestCase {

    private var savedMemoriesEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        savedMemoriesEnabled = AppSettings.shared.memoriesEnabled
        AppSettings.shared.memoriesEnabled = true
    }

    override func tearDown() async throws {
        AppSettings.shared.memoriesEnabled = savedMemoriesEnabled
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeEngine(
        provider: MockProvider = MockProvider(responses: [.text("ok")]),
        xcalibreClient: (any XcalibreClientProtocol)? = nil
    ) -> AgenticEngine {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let engine = AgenticEngine(
            proProvider: provider,
            flashProvider: provider,
            visionProvider: LMStudioProvider(),
            toolRouter: router,
            contextManager: ContextManager(),
            xcalibreClient: xcalibreClient
        )
        engine.criticOverride = AlwaysPassCritic()
        engine.classifierOverride = StubClassifier(complexity: .standard)
        return engine
    }

    // MARK: - Injection

    func testSetMemoryBackendCompiles() async {
        let engine = makeEngine(provider: MockProvider(responses: [.text("hi")]))
        await engine.setMemoryBackend(NullMemoryPlugin())
    }

    // MARK: - Episodic write

    func testEpisodicWriteGoesToBackendAfterTurn() async throws {
        let backend = CapturingMemoryBackend()
        let xcalibre = XcalibreClientSpy(bookChunks: [])
        let engine = makeEngine(xcalibreClient: xcalibre)
        await engine.setMemoryBackend(backend)

        for await _ in engine.send(userMessage: "Hello") {}

        let written = await backend.writtenChunks
        XCTAssertFalse(written.isEmpty, "Episodic chunk should have been written after turn")
        XCTAssertEqual(written.first?.chunkType, "episodic")
        let xcalibreWriteCount = await xcalibre.writeCallCount
        XCTAssertEqual(xcalibreWriteCount, 0)
    }

    func testCriticFailSuppressesBackendWrite() async throws {
        let backend = CapturingMemoryBackend()
        let engine = makeEngine()
        await engine.setMemoryBackend(backend)
        engine.criticOverride = AlwaysFailCritic()

        for await _ in engine.send(userMessage: "Test") {}

        let written = await backend.writtenChunks
        XCTAssertTrue(written.isEmpty, "Critic .fail should suppress episodic write")
    }

    func testCriticPassAllowsBackendWrite() async throws {
        let backend = CapturingMemoryBackend()
        let engine = makeEngine()
        await engine.setMemoryBackend(backend)
        engine.criticOverride = AlwaysPassCritic()

        for await _ in engine.send(userMessage: "Test") {}

        let written = await backend.writtenChunks
        XCTAssertFalse(written.isEmpty, "Critic .pass should allow episodic write")
    }

    // MARK: - RAG search

    func testMemorySearchResultsAppearInRAGContext() async throws {
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(
                    id: "m1",
                    content: "user prefers dark mode",
                    chunkType: "factual"
                ),
                score: 0.9
            )
        ])
        let engine = makeEngine()
        await engine.setMemoryBackend(backend)

        var ragChunks: [RAGChunk] = []
        for await event in engine.send(userMessage: "What display mode does the user prefer?") {
            if case .ragSources(let chunks) = event {
                ragChunks = chunks
            }
        }

        XCTAssertFalse(ragChunks.isEmpty,
                       "RAG sources event should fire when memory backend returns results")
        XCTAssertTrue(ragChunks.contains(where: { $0.source == "memory" }))
    }

    func testXcalibreBookSearchStillFiresWhenClientIsSet() async throws {
        let xcalibre = XcalibreClientSpy(bookChunks: [
            RAGChunk(
                chunkID: "b1",
                source: "books",
                chunkType: "chapter",
                text: "book text",
                rrfScore: 0.8
            )
        ])
        let engine = makeEngine(xcalibreClient: xcalibre)
        await engine.setMemoryBackend(FixedSearchMemoryBackend(results: []))

        for await _ in engine.send(userMessage: "Search the book content") {}

        let searchCount = await xcalibre.searchChunksCallCount
        XCTAssertGreaterThan(searchCount, 0)
    }
}

// MARK: - Test doubles

private struct AlwaysFailCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .fail(reason: "always fail")
    }
}

private struct AlwaysPassCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .pass
    }
}

private struct StubClassifier: PlannerEngineProtocol {
    let complexity: ComplexityTier

    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        ClassifierResult(needsPlanning: false, complexity: complexity, reason: "stub")
    }

    func decompose(task: String, context: [Message]) async -> [PlanStep] { [] }
}

private actor FixedSearchMemoryBackend: MemoryBackendPlugin {
    nonisolated let pluginID = "fixed-search"
    nonisolated let displayName = "Fixed search (test)"
    private let results: [MemorySearchResult]

    init(results: [MemorySearchResult]) {
        self.results = results
    }

    func write(_ chunk: MemoryChunk) async throws {}

    func search(query: String, topK: Int) async throws -> [MemorySearchResult] {
        Array(results.prefix(topK))
    }

    func delete(id: String) async throws {}
}

private actor XcalibreClientSpy: XcalibreClientProtocol {
    private let bookChunks: [RAGChunk]
    private(set) var searchChunksCallCount = 0
    private(set) var writeCallCount = 0

    init(bookChunks: [RAGChunk]) {
        self.bookChunks = bookChunks
    }

    func probe() async {}

    func isAvailable() async -> Bool { true }

    func searchChunks(
        query: String,
        source: String,
        bookIDs: [String]?,
        projectPath: String?,
        limit: Int,
        rerank: Bool
    ) async -> [RAGChunk] {
        searchChunksCallCount += 1
        return Array(bookChunks.prefix(limit))
    }

    func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk] {
        []
    }

    func writeMemoryChunk(
        text: String,
        chunkType: String,
        sessionID: String?,
        projectPath: String?,
        tags: [String]
    ) async -> String? {
        writeCallCount += 1
        return "mem-\(writeCallCount)"
    }

    func deleteMemoryChunk(id: String) async {}

    func listBooks(limit: Int) async -> [RAGBook] { [] }
}
