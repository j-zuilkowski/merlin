import XCTest
@testable import Merlin

@MainActor
final class GroundingConfidenceTests: XCTestCase {

    private var savedFreshnessThreshold: Int = 90
    private var savedMinGroundingScore: Double = 0.30

    override func setUp() async throws {
        try await super.setUp()
        savedFreshnessThreshold = AppSettings.shared.ragFreshnessThresholdDays
        savedMinGroundingScore = AppSettings.shared.ragMinGroundingScore
        AppSettings.shared.ragFreshnessThresholdDays = 90
        AppSettings.shared.ragMinGroundingScore = 0.30
    }

    override func tearDown() async throws {
        AppSettings.shared.ragFreshnessThresholdDays = savedFreshnessThreshold
        AppSettings.shared.ragMinGroundingScore = savedMinGroundingScore
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeEngine(
        backend: (any MemoryBackendPlugin)? = nil,
        xcalibreClient: (any XcalibreClientProtocol)? = nil
    ) -> AgenticEngine {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let engine = AgenticEngine(
            proProvider: MockProvider(responses: [.text("ok")]),
            flashProvider: MockProvider(responses: [.text("ok")]),
            visionProvider: MockProvider(responses: [.text("ok")]),
            toolRouter: router,
            contextManager: ContextManager(),
            xcalibreClient: xcalibreClient,
            memoryBackend: backend
        )
        engine.criticOverride = AlwaysPassCritic()
        engine.classifierOverride = StubClassifier()
        return engine
    }

    private func groundingReport(
        from engine: AgenticEngine,
        message: String = "hello"
    ) async -> GroundingReport? {
        var report: GroundingReport?
        for await event in engine.send(userMessage: message) {
            if case .groundingReport(let value) = event {
                report = value
            }
        }
        return report
    }

    // MARK: - Emission

    func testGroundingReportEmittedEachTurn() async throws {
        let engine = makeEngine()
        let report = await groundingReport(from: engine)
        XCTAssertNotNil(report, "groundingReport event must be emitted every turn")
    }

    func testTotalChunksZeroWhenNoRAG() async throws {
        let engine = makeEngine()
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.totalChunks, 0)
    }

    func testIsWellGroundedFalseWhenNoChunks() async throws {
        let engine = makeEngine()
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.isWellGrounded, false)
    }

    // MARK: - Chunk counting

    func testMemoryChunksCountsOnlyMemorySource() async throws {
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "m1", content: "memory content", chunkType: "factual"),
                score: 0.8
            )
        ])
        let engine = makeEngine(backend: backend)
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.memoryChunks, 1)
        XCTAssertEqual(report?.bookChunks, 0)
    }

    func testBookChunksCountOnlyNonMemorySources() async throws {
        let xcalibre = XcalibreClientSpy(bookChunks: [
            RAGChunk(
                chunkID: "b1",
                source: "books",
                chunkType: "chapter",
                text: "book content",
                rrfScore: 0.9
            )
        ])
        let engine = makeEngine(xcalibreClient: xcalibre)
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.memoryChunks, 0)
        XCTAssertEqual(report?.bookChunks, 1)
    }

    func testTotalChunksIsSumOfMemoryAndBook() async throws {
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "m1", content: "mem", chunkType: "factual"),
                score: 0.75
            )
        ])
        let xcalibre = XcalibreClientSpy(bookChunks: [
            RAGChunk(
                chunkID: "b1",
                source: "books",
                chunkType: "chapter",
                text: "book",
                rrfScore: 0.9
            )
        ])
        let engine = makeEngine(backend: backend, xcalibreClient: xcalibre)
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.totalChunks, (report?.memoryChunks ?? 0) + (report?.bookChunks ?? 0))
    }

    // MARK: - Average score

    func testAverageScoreIsZeroWhenNoChunks() async throws {
        let engine = makeEngine()
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.averageScore ?? 0, 0, accuracy: 0.001)
    }

    func testAverageScoreComputedFromAllChunks() async throws {
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "m1", content: "a", chunkType: "factual"),
                score: 0.6
            )
        ])
        let xcalibre = XcalibreClientSpy(bookChunks: [
            RAGChunk(
                chunkID: "b1",
                source: "books",
                chunkType: "chapter",
                text: "b",
                rrfScore: 0.8
            )
        ])
        let engine = makeEngine(backend: backend, xcalibreClient: xcalibre)
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.averageScore ?? 0, 0.7, accuracy: 0.01)
    }

    // MARK: - Staleness

    func testHasStaleMemoryTrueWhenChunkExceedsThreshold() async throws {
        AppSettings.shared.ragFreshnessThresholdDays = 30
        let oldDate = Calendar.current.date(byAdding: .day, value: -91, to: Date())!
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(
                    id: "old",
                    content: "old content",
                    chunkType: "factual",
                    createdAt: oldDate
                ),
                score: 0.7
            )
        ])
        let engine = makeEngine(backend: backend)
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.hasStaleMemory, true)
    }

    func testHasStaleMemoryFalseWhenAllChunksFresh() async throws {
        AppSettings.shared.ragFreshnessThresholdDays = 90
        let recentDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(
                    id: "fresh",
                    content: "fresh content",
                    chunkType: "factual",
                    createdAt: recentDate
                ),
                score: 0.8
            )
        ])
        let engine = makeEngine(backend: backend)
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.hasStaleMemory, false)
    }

    // MARK: - isWellGrounded

    func testIsWellGroundedFalseWhenBelowMinScore() async throws {
        AppSettings.shared.ragMinGroundingScore = 0.5
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "weak", content: "weak", chunkType: "factual"),
                score: 0.2
            )
        ])
        let engine = makeEngine(backend: backend)
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.isWellGrounded, false)
    }

    func testIsWellGroundedTrueWhenChunksPresentAndScoreAboveThreshold() async throws {
        AppSettings.shared.ragMinGroundingScore = 0.3
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "good", content: "good content", chunkType: "factual"),
                score: 0.8
            )
        ])
        let engine = makeEngine(backend: backend)
        let report = await groundingReport(from: engine)
        XCTAssertEqual(report?.isWellGrounded, true)
    }

    // MARK: - AppSettings defaults

    func testFreshnessThresholdDefaultIs90() {
        XCTAssertEqual(AppSettings.shared.ragFreshnessThresholdDays, 90)
    }

    func testMinGroundingScoreDefaultIs0Point30() {
        XCTAssertEqual(AppSettings.shared.ragMinGroundingScore, 0.30, accuracy: 0.001)
    }
}

// MARK: - Test Doubles

private struct AlwaysPassCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .pass
    }
}

private struct StubClassifier: PlannerEngineProtocol {
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        ClassifierResult(needsPlanning: false, complexity: .standard, reason: "stub")
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
        Array(bookChunks.prefix(limit))
    }

    func writeMemoryChunk(
        text: String,
        chunkType: String,
        sessionID: String?,
        projectPath: String?,
        tags: [String]
    ) async -> String? {
        nil
    }

    func deleteMemoryChunk(id: String) async {}

    func listBooks(limit: Int) async -> [RAGBook] { [] }
}
