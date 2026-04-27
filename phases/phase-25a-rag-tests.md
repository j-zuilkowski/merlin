# Phase 25a — RAG Integration Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

RAG source: xcalibre-server (Rust/Axum) running at http://localhost:8083.
Primary endpoint: GET /api/v1/search/chunks
Books endpoint:   GET /api/v1/books
Health endpoint:  GET /health (no auth)
Auth: Bearer token from Keychain (service: com.merlin.xcalibre, account: api-token)

Graceful degradation required: all RAG operations return empty/nil on any error or unavailability.
Never throw to the caller. Never block the agent loop.

TDD coverage:
  File 1 — XcalibreClientTests: probe, searchChunks, listBooks, Keychain round-trip
  File 2 — RAGToolsTests: formatting helpers + tool handler functions (search, listBooks)
  File 3 — RAGEngineTests: AgenticEngine auto-inject behaviour

---

## Write to: MerlinTests/Unit/XcalibreClientTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - Mock HTTP fetcher

final class MockHTTPFetcher: HTTPFetching, @unchecked Sendable {
    // Keyed by URL path. Returns 404 for unregistered paths.
    var responses: [String: (Data, Int)] = [:]
    var stubbedError: Error? = nil
    // Captures every URLRequest for inspection in tests
    private(set) var capturedRequests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        if let error = stubbedError { throw error }
        let path = request.url?.path ?? ""
        let (data, status) = responses[path] ?? (Data(), 404)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

// MARK: - Shared fixtures

private let sampleChunkJSON = """
{
    "query": "closures",
    "chunks": [
        {
            "chunk_id": "abc123",
            "book_id": "book1",
            "book_title": "Swift Programming",
            "heading_path": "Closures › Capturing Values",
            "chunk_type": "paragraph",
            "text": "Closures capture constants and variables from context.",
            "word_count": 8,
            "bm25_score": 0.9,
            "cosine_score": 0.85,
            "rrf_score": 0.95,
            "rerank_score": null
        }
    ],
    "total_searched": 100,
    "retrieval_ms": 42
}
"""

private let sampleBooksJSON = """
{
    "items": [
        {
            "id": "book1",
            "title": "Swift Programming Language",
            "sort_title": "swift programming language",
            "document_type": "epub",
            "authors": [{"id": "a1", "name": "Apple Inc."}],
            "tags": [],
            "formats": [],
            "has_cover": false,
            "is_read": false,
            "is_archived": false,
            "identifiers": [],
            "created_at": "2024-01-01T00:00:00Z",
            "last_modified": "2024-01-01T00:00:00Z"
        }
    ],
    "total": 1
}
"""

// MARK: - XcalibreClientTests

final class XcalibreClientTests: XCTestCase {

    // MARK: Probe

    func testProbeSetsTrueOnSuccess() async {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        let available = await client.isAvailable
        XCTAssertTrue(available)
    }

    func testProbeSetsFalseOnNetworkError() async {
        let mock = MockHTTPFetcher()
        mock.stubbedError = URLError(.cannotConnectToHost)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        let available = await client.isAvailable
        XCTAssertFalse(available)
    }

    func testProbeSetsFalseOnNon200() async {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 503)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        let available = await client.isAvailable
        XCTAssertFalse(available)
    }

    // MARK: Search chunks

    func testSearchChunksReturnsChunks() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(sampleChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        try XcalibreClient.writeAPIToken("test-token")
        let chunks = await client.searchChunks(query: "closures")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].bookTitle, "Swift Programming")
        XCTAssertEqual(chunks[0].headingPath, "Closures › Capturing Values")
        XCTAssertEqual(chunks[0].text, "Closures capture constants and variables from context.")
    }

    func testSearchChunksReturnsEmptyWhenUnavailable() async {
        let mock = MockHTTPFetcher()
        // No health response — stays unavailable
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        let chunks = await client.searchChunks(query: "anything")
        XCTAssertTrue(chunks.isEmpty)
    }

    func testSearchChunksReturnsEmptyOnNon200() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(), 503)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        try XcalibreClient.writeAPIToken("test-token")
        let chunks = await client.searchChunks(query: "anything")
        XCTAssertTrue(chunks.isEmpty)
        // Availability should be set false after non-200
        let available = await client.isAvailable
        XCTAssertFalse(available)
    }

    func testSearchChunksReturnsEmptyOnMalformedJSON() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data("not json".utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        try XcalibreClient.writeAPIToken("test-token")
        let chunks = await client.searchChunks(query: "anything")
        XCTAssertTrue(chunks.isEmpty)
    }

    // MARK: List books

    func testListBooksReturnsBooks() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/books"] = (Data(sampleBooksJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        try XcalibreClient.writeAPIToken("test-token")
        let books = await client.listBooks()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Swift Programming Language")
        XCTAssertEqual(books[0].id, "book1")
    }

    func testListBooksReturnsEmptyWhenUnavailable() async {
        let mock = MockHTTPFetcher()
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        let books = await client.listBooks()
        XCTAssertTrue(books.isEmpty)
    }

    // MARK: Keychain

    func testWriteAndReadAPIToken() throws {
        let token = "xcalibre-test-\(UUID().uuidString)"
        try XcalibreClient.writeAPIToken(token)
        let read = XcalibreClient.readAPIToken()
        XCTAssertEqual(read, token)
    }
}
```

---

## Write to: MerlinTests/Unit/RAGToolsTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - RAGToolsTests (formatting helpers)

final class RAGToolsTests: XCTestCase {

    func testBuildEnrichedMessagePrependsContext() {
        let chunks = [
            RAGChunk(
                chunkID: "c1", bookID: "b1", bookTitle: "Swift Book",
                headingPath: "Generics", chunkType: "paragraph",
                text: "Generic code enables flexible, reusable functions.",
                wordCount: 8, rrfScore: 0.9, rerankScore: nil
            )
        ]
        let result = RAGTools.buildEnrichedMessage("How do generics work?", chunks: chunks)
        XCTAssertTrue(result.hasPrefix("[Relevant passages from your library]"))
        XCTAssertTrue(result.contains("Swift Book › Generics"))
        XCTAssertTrue(result.contains("Generic code enables flexible"))
        XCTAssertTrue(result.contains("How do generics work?"))
    }

    func testBuildEnrichedMessageReturnsOriginalWhenNoChunks() {
        let result = RAGTools.buildEnrichedMessage("How do generics work?", chunks: [])
        XCTAssertEqual(result, "How do generics work?")
    }

    func testBuildEnrichedMessageHandlesMissingHeadingPath() {
        let chunks = [
            RAGChunk(
                chunkID: "c1", bookID: "b1", bookTitle: "Swift Book",
                headingPath: nil, chunkType: "paragraph",
                text: "Some text.", wordCount: 2, rrfScore: 0.5, rerankScore: nil
            )
        ]
        let result = RAGTools.buildEnrichedMessage("query", chunks: chunks)
        XCTAssertTrue(result.contains("Swift Book"))
        XCTAssertFalse(result.contains("Swift Book ›"))
    }

    func testFormatChunksProducesNumberedList() {
        let chunks = [
            RAGChunk(chunkID: "1", bookID: "b1", bookTitle: "Book A",
                     headingPath: "Chapter 1", chunkType: "paragraph",
                     text: "First chunk.", wordCount: 2, rrfScore: 0.9, rerankScore: nil),
            RAGChunk(chunkID: "2", bookID: "b1", bookTitle: "Book A",
                     headingPath: "Chapter 2", chunkType: "paragraph",
                     text: "Second chunk.", wordCount: 2, rrfScore: 0.8, rerankScore: nil),
        ]
        let result = RAGTools.formatChunks(chunks)
        XCTAssertTrue(result.contains("[1]"))
        XCTAssertTrue(result.contains("[2]"))
        XCTAssertTrue(result.contains("First chunk."))
        XCTAssertTrue(result.contains("Second chunk."))
    }

    func testFormatBooksProducesNumberedList() {
        let books = [
            RAGBook(id: "b1", title: "Swift Book", authors: [RAGAuthorRef(name: "Apple")]),
            RAGBook(id: "b2", title: "Rust Book", authors: []),
        ]
        let result = RAGTools.formatBooks(books)
        XCTAssertTrue(result.contains("1."))
        XCTAssertTrue(result.contains("[b1]"))
        XCTAssertTrue(result.contains("Swift Book"))
        XCTAssertTrue(result.contains("Apple"))
        XCTAssertTrue(result.contains("2."))
        XCTAssertTrue(result.contains("[b2]"))
    }
}

// MARK: - RAGToolsHandlerTests (tool dispatch functions)

final class RAGToolsHandlerTests: XCTestCase {

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

    private let booksJSON = """
    {
        "items": [
            {
                "id": "b1", "title": "Swift Book",
                "sort_title": "swift book", "document_type": "epub",
                "authors": [{"id": "a1", "name": "Apple"}],
                "tags": [], "formats": [], "has_cover": false,
                "is_read": false, "is_archived": false, "identifiers": [],
                "created_at": "2024-01-01T00:00:00Z",
                "last_modified": "2024-01-01T00:00:00Z"
            }
        ],
        "total": 1
    }
    """

    private func makeAvailableClient(
        searchResponse: String? = nil,
        booksResponse: String? = nil
    ) async throws -> XcalibreClient {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        if let s = searchResponse {
            mock.responses["/api/v1/search/chunks"] = (Data(s.utf8), 200)
        }
        if let b = booksResponse {
            mock.responses["/api/v1/books"] = (Data(b.utf8), 200)
        }
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        try XcalibreClient.writeAPIToken("test-token")
        return client
    }

    // MARK: search

    func testSearchReturnsFormattedChunks() async throws {
        let client = try await makeAvailableClient(searchResponse: chunkJSON)
        let result = await RAGTools.search(args: #"{"query":"closures"}"#, client: client)
        XCTAssertTrue(result.contains("[1]"), "Expected numbered list")
        XCTAssertTrue(result.contains("Swift Book"))
        XCTAssertTrue(result.contains("Closures capture values."))
    }

    func testSearchReturnsUnavailableMessageWhenClientUnavailable() async {
        let mock = MockHTTPFetcher() // no /health response — stays unavailable
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        let result = await RAGTools.search(args: #"{"query":"anything"}"#, client: client)
        XCTAssertTrue(result.lowercased().contains("unavailable"))
    }

    func testSearchHandlesInvalidJSONArgs() async throws {
        let client = try await makeAvailableClient(searchResponse: chunkJSON)
        let result = await RAGTools.search(args: "not json at all", client: client)
        XCTAssertTrue(result.lowercased().contains("invalid"))
    }

    func testSearchReturnsNoResultsMessageWhenChunksEmpty() async throws {
        // Server returns valid JSON with empty chunks array
        let emptyChunksJSON = """
        {"query":"nothing","chunks":[],"total_searched":0,"retrieval_ms":1}
        """
        let client = try await makeAvailableClient(searchResponse: emptyChunksJSON)
        let result = await RAGTools.search(args: #"{"query":"nothing"}"#, client: client)
        XCTAssertTrue(result.lowercased().contains("no relevant passages"))
    }

    func testSearchClampsLimitTo20() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(chunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        await client.probe()
        try XcalibreClient.writeAPIToken("test-token")

        _ = await RAGTools.search(args: #"{"query":"test","limit":999}"#, client: client)

        // Verify the actual HTTP request used limit=20, not 999
        let searchReq = mock.capturedRequests.first {
            $0.url?.path == "/api/v1/search/chunks"
        }
        let components = URLComponents(url: searchReq!.url!, resolvingAgainstBaseURL: false)
        let limitItem = components?.queryItems?.first { $0.name == "limit" }
        XCTAssertEqual(limitItem?.value, "20", "limit must be clamped to 20")
    }

    // MARK: listBooks

    func testListBooksReturnsFormattedList() async throws {
        let client = try await makeAvailableClient(booksResponse: booksJSON)
        let result = await RAGTools.listBooks(client: client)
        XCTAssertTrue(result.contains("1."))
        XCTAssertTrue(result.contains("[b1]"))
        XCTAssertTrue(result.contains("Swift Book"))
        XCTAssertTrue(result.contains("Apple"))
    }

    func testListBooksReturnsUnavailableMessageWhenClientUnavailable() async {
        let mock = MockHTTPFetcher()
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        let result = await RAGTools.listBooks(client: client)
        XCTAssertTrue(result.lowercased().contains("unavailable"))
    }
}
```

---

## Write to: MerlinTests/Unit/RAGEngineTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - CapturingProvider
// If a mock LLM provider is already defined in AgenticEngineTests.swift,
// consolidate both into MerlinTests/Helpers/TestProviders.swift.

final class CapturingProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let baseURL = URL(string: "http://localhost")!
    private(set) var capturedRequests: [CompletionRequest] = []

    init(id: String = "capturing") { self.id = id }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        capturedRequests.append(request)
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: .init(content: "ok"), finishReason: nil))
            c.yield(CompletionChunk(delta: nil, finishReason: "stop"))
            c.finish()
        }
    }
}

// MARK: - RAGEngineTests

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

    // Builds an engine wired with a CapturingProvider and optional XcalibreClient.
    // Adjust LMStudioProvider init to match your phase-04 implementation.
    private func makeEngine(
        xcalibreClient: XcalibreClient? = nil
    ) -> (AgenticEngine, CapturingProvider, ContextManager) {
        let capturing = CapturingProvider()
        let ctx = ContextManager()
        let engine = AgenticEngine(
            proProvider: capturing,
            flashProvider: capturing,
            visionProvider: LMStudioProvider(),
            toolRouter: ToolRouter(),
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

        for try await _ in engine.runLoop(userMessage: "What are closures?") {}

        let userMsg = ctx.messages.first { $0.role == .user }
        XCTAssertNotNil(userMsg, "Context should contain a user message")
        guard case .text(let content) = userMsg?.content else {
            return XCTFail("Expected text content")
        }
        XCTAssertTrue(
            content.hasPrefix("[Relevant passages from your library]"),
            "User message should be enriched with RAG prefix"
        )
        XCTAssertTrue(content.contains("What are closures?"),
                      "Original message should be preserved after RAG prefix")
    }

    func testAutoInjectPassesThroughWhenClientReturnsNoChunks() async throws {
        // Empty chunks — server returns nothing
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
        for try await _ in engine.runLoop(userMessage: "plain question") {}

        guard case .text(let content) = ctx.messages.first(where: { $0.role == .user })?.content else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(content, "plain question",
                       "Message should be unchanged when no chunks returned")
    }

    func testAutoInjectSkipsWhenNoClientConfigured() async throws {
        let (engine, _, ctx) = makeEngine(xcalibreClient: nil)
        for try await _ in engine.runLoop(userMessage: "plain question") {}

        guard case .text(let content) = ctx.messages.first(where: { $0.role == .user })?.content else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(content, "plain question",
                       "Message should be unchanged when xcalibreClient is nil")
    }
}
```

---

## Verify

Run after writing the files. Expect build errors for missing types.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -30
```

Expected: `BUILD FAILED` with errors referencing `XcalibreClient`, `RAGChunk`, `RAGBook`,
`RAGAuthorRef`, `HTTPFetching`, `RAGTools`, `CapturingProvider`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/XcalibreClientTests.swift \
        MerlinTests/Unit/RAGToolsTests.swift \
        MerlinTests/Unit/RAGEngineTests.swift
git commit -m "Phase 25a — XcalibreClientTests + RAGToolsTests + RAGEngineTests (failing)"
```
