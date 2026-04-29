import XCTest
@testable import Merlin

// MARK: - RAGToolsTests (formatting helpers)

final class RAGToolsTests: XCTestCase {

    func testBuildEnrichedMessagePrependsContext() {
        let chunks = [
            RAGChunk(
                chunkID: "c1", source: "books", bookID: "b1", bookTitle: "Swift Book",
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
                chunkID: "c1", source: "books", bookID: "b1", bookTitle: "Swift Book",
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
            RAGChunk(chunkID: "1", source: "books", bookID: "b1", bookTitle: "Book A",
                     headingPath: "Chapter 1", chunkType: "paragraph",
                     text: "First chunk.", wordCount: 2, rrfScore: 0.9, rerankScore: nil),
            RAGChunk(chunkID: "2", source: "books", bookID: "b1", bookTitle: "Book A",
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
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "test-token", fetcher: mock)
        await client.probe()
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
        let mock = MockHTTPFetcher() // no /health response - stays unavailable
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
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "test-token", fetcher: mock)
        await client.probe()

        _ = await RAGTools.search(args: #"{"query":"test","limit":999}"#, client: client)

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
