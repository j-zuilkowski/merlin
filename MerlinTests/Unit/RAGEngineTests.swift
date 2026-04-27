import XCTest
@testable import Merlin

// MARK: - CapturingProvider

final class CapturingProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let baseURL = URL(string: "http://localhost")!
    private(set) var capturedRequests: [CompletionRequest] = []

    init(id: String = "capturing") {
        self.id = id
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        capturedRequests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(delta: .init(content: "ok"), finishReason: nil))
            continuation.yield(CompletionChunk(delta: nil, finishReason: "stop"))
            continuation.finish()
        }
    }
}

// MARK: - RAGEngineTests

@MainActor
final class RAGEngineTests: XCTestCase {

    private let chunkJSON = """
    {
        "query": "closures",
        "chunks": [
            {
                "chunk_id": "c1", "book_id": "b1", "book_title": "Swift Book",
                "heading_path": "Closures", "chunk_type": "paragraph",
                "text": "Closures capture values.", "word_count": 4,
                "bm25_score": 0.9, "cosine_score": 0.8,
                "rrf_score": 0.95, "rerank_score": null
            }
        ],
        "total_searched": 10, "retrieval_ms": 5
    }
    """

    private func makeEngine(
        xcalibreClient: XcalibreClient? = nil
    ) -> (AgenticEngine, CapturingProvider, ContextManager) {
        let capturing = CapturingProvider()
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let ctx = ContextManager()
        let engine = AgenticEngine(
            proProvider: capturing,
            flashProvider: capturing,
            visionProvider: LMStudioProvider(),
            toolRouter: router,
            contextManager: ctx,
            xcalibreClient: xcalibreClient
        )
        return (engine, capturing, ctx)
    }

    private func makeAvailableClient() async throws -> XcalibreClient {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(chunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        try XcalibreClient.writeAPIToken("test-token")
        return client
    }

    // MARK: Auto-inject

    func testAutoInjectEnrichesUserMessageWhenChunksAvailable() async throws {
        let client = try await makeAvailableClient()
        let (engine, _, ctx) = makeEngine(xcalibreClient: client)

        for await _ in engine.send(userMessage: "What are closures?") {}

        let userMsg = ctx.messages.first { $0.role == .user }
        XCTAssertNotNil(userMsg, "Context should contain a user message")
        guard case .text(let content) = userMsg?.content else {
            return XCTFail("Expected text content")
        }
        XCTAssertTrue(
            content.hasPrefix("[Relevant passages from your library]"),
            "User message should be enriched with RAG prefix"
        )
        XCTAssertTrue(
            content.contains("What are closures?"),
            "Original message should be preserved after RAG prefix"
        )
    }

    func testAutoInjectPassesThroughWhenClientReturnsNoChunks() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        let emptyChunksJSON = """
        {"query":"test","chunks":[],"total_searched":0,"retrieval_ms":1}
        """
        mock.responses["/api/v1/search/chunks"] = (Data(emptyChunksJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        try XcalibreClient.writeAPIToken("test-token")

        let (engine, _, ctx) = makeEngine(xcalibreClient: client)
        for await _ in engine.send(userMessage: "plain question") {}

        guard case .text(let content) = ctx.messages.first(where: { $0.role == .user })?.content else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(
            content,
            "plain question",
            "Message should be unchanged when no chunks returned"
        )
    }

    func testAutoInjectSkipsWhenNoClientConfigured() async throws {
        let (engine, _, ctx) = makeEngine(xcalibreClient: nil)
        for await _ in engine.send(userMessage: "plain question") {}

        guard case .text(let content) = ctx.messages.first(where: { $0.role == .user })?.content else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(
            content,
            "plain question",
            "Message should be unchanged when xcalibreClient is nil"
        )
    }
}
