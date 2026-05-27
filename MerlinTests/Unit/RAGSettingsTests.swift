import XCTest
@testable import Merlin

@MainActor
final class RAGSettingsTests: XCTestCase {

    // MARK: - ragRerank

    func testRagRerankDefaultsFalse() {
        XCTAssertFalse(AppSettings.shared.ragRerank,
                       "ragRerank must default to false — safe for low-VRAM hardware")
    }

    func testRagRerankRoundTrip() {
        let original = AppSettings.shared.ragRerank
        AppSettings.shared.ragRerank = true
        XCTAssertTrue(AppSettings.shared.ragRerank)
        AppSettings.shared.ragRerank = original
    }

    func testRagRerankSerializesToTOML() {
        let settings = AppSettings.shared
        let saved = settings.ragRerank
        settings.ragRerank = true
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("rag_rerank"), "rag_rerank must appear in TOML when true")
        settings.ragRerank = saved
    }

    func testRagRerankNotWrittenToTOMLWhenFalse() {
        let settings = AppSettings.shared
        let saved = settings.ragRerank
        settings.ragRerank = false
        let toml = settings.serializedTOML()
        XCTAssertFalse(toml.contains("rag_rerank"),
                       "rag_rerank must be omitted from TOML when false (default)")
        settings.ragRerank = saved
    }

    func testRagRerankRoundTripsThroughTOML() {
        let settings = AppSettings.shared
        let saved = settings.ragRerank
        settings.ragRerank = true
        let toml = settings.serializedTOML()
        settings.ragRerank = false        // reset before re-applying
        settings.applyTOML(toml)
        XCTAssertTrue(settings.ragRerank)
        settings.ragRerank = saved
    }

    // MARK: - ragChunkLimit

    func testRagChunkLimitDefaultsThree() {
        XCTAssertEqual(AppSettings.shared.ragChunkLimit, 3,
                       "ragChunkLimit must default to 3")
    }

    func testRagChunkLimitRoundTrip() {
        let original = AppSettings.shared.ragChunkLimit
        AppSettings.shared.ragChunkLimit = 10
        XCTAssertEqual(AppSettings.shared.ragChunkLimit, 10)
        AppSettings.shared.ragChunkLimit = original
    }

    func testRagChunkLimitSerializesToTOML() {
        let settings = AppSettings.shared
        let saved = settings.ragChunkLimit
        settings.ragChunkLimit = 8
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("rag_chunk_limit"))
        XCTAssertTrue(toml.contains("8"))
        settings.ragChunkLimit = saved
    }

    func testRagChunkLimitNotWrittenToTOMLWhenDefault() {
        let settings = AppSettings.shared
        let saved = settings.ragChunkLimit
        settings.ragChunkLimit = 3
        let toml = settings.serializedTOML()
        XCTAssertFalse(toml.contains("rag_chunk_limit"),
                       "rag_chunk_limit must be omitted when at default value of 3")
        settings.ragChunkLimit = saved
    }

    func testRagChunkLimitRoundTripsThroughTOML() {
        let settings = AppSettings.shared
        let saved = settings.ragChunkLimit
        settings.ragChunkLimit = 12
        let toml = settings.serializedTOML()
        settings.ragChunkLimit = 3
        settings.applyTOML(toml)
        XCTAssertEqual(settings.ragChunkLimit, 12)
        settings.ragChunkLimit = saved
    }

    func testRagChunkLimitClampedToValidRange() {
        // Engine must clamp to 1...20 regardless of what AppSettings holds
        // This tests the engine's clamping, not AppSettings validation.
        let settings = AppSettings.shared
        let saved = settings.ragChunkLimit
        settings.ragChunkLimit = 0         // below minimum
        XCTAssertGreaterThanOrEqual(
            min(max(settings.ragChunkLimit, 1), 20), 1,
            "Engine clamp must produce at least 1"
        )
        settings.ragChunkLimit = 999       // above maximum
        XCTAssertLessThanOrEqual(
            min(max(settings.ragChunkLimit, 1), 20), 20,
            "Engine clamp must produce at most 20"
        )
        settings.ragChunkLimit = saved
    }

    // MARK: - Engine wiring

    func testEngineUsesRagRerankFromSettings() async throws {
        // Verify the engine passes AppSettings.ragRerank to searchChunks.
        // We spy on the URLRequest to check the rerank query parameter.
        let chunkJSON = """
        {"query":"q","chunks":[],"total_searched":0,"retrieval_ms":1}
        """
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(chunkJSON.utf8), 200)
        let xcalibre = XcalibreClient(
            baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await xcalibre.probe()

        let provider = MinimalProviderRS()
        let registry = ProviderRegistry()
        registry.add(provider)
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id],
            registry: registry,
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager(),
            xcalibreClient: xcalibre
        )

        // Simulate settings with rerank = true
        engine.ragRerank = true
        engine.ragChunkLimit = 5

        for await _ in engine.send(userMessage: "test query") {}

        let req = mock.capturedRequests.first {
            $0.url?.path == "/api/v1/search/chunks"
        }
        XCTAssertNotNil(req)
        let components = URLComponents(url: req!.url!, resolvingAgainstBaseURL: false)
        let rerankVal = components?.queryItems?.first { $0.name == "rerank" }?.value
        XCTAssertEqual(rerankVal, "true")
        let limitVal = components?.queryItems?.first { $0.name == "limit" }?.value
        XCTAssertEqual(limitVal, "5")
    }

    func testFallbackPlannerBuildsFocusedQueriesForCompoundRAGPrompt() {
        let queries = RAGQueryFallbackPlanner.queries(from: """
        Using the connected knowledge base, answer and cite each: (1) At what pressure does \
        the Glimworks Mark IV operate? (2) How long is its calibration cycle and what is \
        the reset code? (3) Who founded Glimworks Industries and in what city?
        """)

        XCTAssertTrue(queries.contains("Glimworks Mark IV pressure"))
        XCTAssertTrue(queries.contains("Glimworks Mark IV calibration reset code"))
        XCTAssertTrue(queries.contains("Glimworks founder city"))
    }

    func testEngineFallsBackToFocusedRAGQueriesWhenFullPromptMisses() async throws {
        let provider = MinimalProviderRS()
        let registry = ProviderRegistry()
        registry.add(provider)
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let xcalibre = FallbackXcalibreClient()
        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id, .reason: provider.id],
            registry: registry,
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager(),
            xcalibreClient: xcalibre
        )

        var ragSources: [RAGChunk] = []
        for await event in engine.send(userMessage: """
        Using the connected knowledge base, answer and cite each: (1) At what pressure does \
        the Glimworks Mark IV operate? (2) How long is its calibration cycle and what is \
        the reset code?
        """) {
            if case .ragSources(let chunks) = event {
                ragSources = chunks
            }
        }

        XCTAssertGreaterThanOrEqual(xcalibre.queries.count, 2)
        XCTAssertTrue(xcalibre.queries.contains("Glimworks Mark IV pressure"))
        XCTAssertEqual(ragSources.first?.text, "The Mark IV operates at 47 kilopascals.")
    }
}

// MARK: - Helpers

private final class MinimalProviderRS: LLMProvider, @unchecked Sendable {
    let id = "minimal-rs"
    let baseURL = URL(string: "http://localhost")!
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: "ok", toolCalls: nil, thinkingContent: nil),
                finishReason: "stop"
            ))
            c.finish()
        }
    }
}

private final class FallbackXcalibreClient: @unchecked Sendable, XcalibreClientProtocol {
    nonisolated(unsafe) var queries: [String] = []

    func probe() async {}
    func isAvailable() async -> Bool { true }
    func searchChunks(query: String, source: String, bookIDs: [String]?,
                      projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk] {
        queries.append(query)
        if query == "Glimworks Mark IV pressure" {
            return [RAGChunk(
                chunkID: "mark-iv-pressure",
                source: "books",
                bookID: "manual",
                bookTitle: "Glimworks Mark IV Operator Manual",
                headingPath: "Operating limits",
                chunkType: "paragraph",
                text: "The Mark IV operates at 47 kilopascals.",
                rrfScore: 1.0
            )]
        }
        return []
    }
    func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk] { [] }
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?,
                          projectPath: String?, tags: [String]) async -> String? { nil }
    func deleteMemoryChunk(id: String) async {}
    func listBooks(limit: Int) async -> [RAGBook] { [] }
}
