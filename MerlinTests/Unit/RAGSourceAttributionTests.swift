import XCTest
@testable import Merlin

@MainActor
final class RAGSourceAttributionTests: XCTestCase {

    // MARK: - AgentEvent.ragSources existence

    func testRagSourcesEventCanBeConstructed() {
        let chunk = RAGChunk(
            chunkID: "c1", source: "books", bookID: "b1", bookTitle: "Swift Book",
            headingPath: "Closures", chunkType: "paragraph",
            text: "Closures capture values.", wordCount: 4, rrfScore: 0.9, rerankScore: nil
        )
        // This test fails to compile if AgentEvent.ragSources doesn't exist.
        let event: AgentEvent = .ragSources([chunk])
        if case .ragSources(let chunks) = event {
            XCTAssertEqual(chunks.count, 1)
        } else {
            XCTFail("Expected .ragSources")
        }
    }

    // MARK: - AgenticEngine emits .ragSources

    func testEngineEmitsRagSourcesWhenChunksFound() async throws {
        let chunkJSON = """
        {
            "query": "closures",
            "chunks": [{
                "chunk_id": "c1", "source": "books",
                "book_id": "b1", "book_title": "Swift Book",
                "heading_path": "Closures", "chunk_type": "paragraph",
                "text": "Closures capture values.", "word_count": 4,
                "bm25_score": 0.9, "cosine_score": 0.8,
                "rrf_score": 0.95, "rerank_score": null
            }],
            "total_searched": 10, "retrieval_ms": 5
        }
        """
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(chunkJSON.utf8), 200)
        let xcalibre = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await xcalibre.probe()

        let provider = ScriptedProviderSA(response: "done")
        let registry = ProviderRegistry()
        registry.add(provider)
        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id],
            registry: registry,
            toolRouter: makeToolRouter(),
            contextManager: ContextManager(),
            xcalibreClient: xcalibre
        )

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "How do closures work?") {
            events.append(event)
        }

        var ragEvents: [[RAGChunk]] = []
        for event in events {
            if case .ragSources(let chunks) = event {
                ragEvents.append(chunks)
            }
        }
        XCTAssertEqual(ragEvents.count, 1, "Exactly one .ragSources event must be emitted")
        XCTAssertEqual(ragEvents.first?.first?.bookTitle, "Swift Book")
    }

    func testEngineDoesNotEmitRagSourcesWhenNoChunks() async throws {
        let emptyJSON = """
        {"query":"q","chunks":[],"total_searched":0,"retrieval_ms":1}
        """
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(emptyJSON.utf8), 200)
        let xcalibre = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await xcalibre.probe()

        let provider = ScriptedProviderSA(response: "done")
        let registry = ProviderRegistry()
        registry.add(provider)
        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id],
            registry: registry,
            toolRouter: makeToolRouter(),
            contextManager: ContextManager(),
            xcalibreClient: xcalibre
        )

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "anything") {
            events.append(event)
        }

        let ragEvents = events.filter {
            if case .ragSources = $0 { return true } else { return false }
        }
        XCTAssertTrue(ragEvents.isEmpty, ".ragSources must not be emitted when no chunks found")
    }

    func testEngineDoesNotEmitRagSourcesWithoutXcalibreClient() async throws {
        let provider = ScriptedProviderSA(response: "done")
        let registry = ProviderRegistry()
        registry.add(provider)
        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id],
            registry: registry,
            toolRouter: makeToolRouter(),
            contextManager: ContextManager()
            // No xcalibreClient
        )

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "anything") {
            events.append(event)
        }

        let ragEvents = events.filter {
            if case .ragSources = $0 { return true } else { return false }
        }
        XCTAssertTrue(ragEvents.isEmpty)
    }

    // MARK: - View type existence

    func testRAGSourcesViewTypeExists() {
        guard ProcessInfo.processInfo.environment["RUN_VIEW_INSTANTIATION"] == "1" else { return }
        _ = RAGSourcesView(chunks: [])
    }
}

// MARK: - Helpers

@MainActor
private func makeToolRouter() -> ToolRouter {
    let memory = AuthMemory(storePath: "/tmp/auth-rag-source-attribution-tests.json")
    memory.addAllowPattern(tool: "*", pattern: "*")
    let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
    return ToolRouter(authGate: gate)
}

private final class ScriptedProviderSA: LLMProvider, @unchecked Sendable {
    let id = "scripted-sa"
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    let response: String
    init(response: String) { self.response = response }
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
