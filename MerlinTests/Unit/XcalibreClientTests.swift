import XCTest
@testable import Merlin

// MARK: - Mock HTTP fetcher

final class MockHTTPFetcher: HTTPFetching, @unchecked Sendable {
    // Keyed by URL path. Returns 404 for unregistered paths.
    var responses: [String: (Data, Int)] = [:]
    var stubbedError: Error? = nil
    // Captures every URLRequest for inspection in tests.
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
            "source": "books",
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
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "test-token", fetcher: mock)
        await client.probe()
        let chunks = await client.searchChunks(query: "closures")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].bookTitle, "Swift Programming")
        XCTAssertEqual(chunks[0].headingPath, "Closures › Capturing Values")
        XCTAssertEqual(chunks[0].text, "Closures capture constants and variables from context.")
    }

    func testSearchChunksReturnsEmptyWhenUnavailable() async {
        let mock = MockHTTPFetcher()
        // No health response - stays unavailable.
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        let chunks = await client.searchChunks(query: "anything")
        XCTAssertTrue(chunks.isEmpty)
    }

    func testSearchChunksReturnsEmptyOnNon200() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(), 503)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "test-token", fetcher: mock)
        await client.probe()
        let chunks = await client.searchChunks(query: "anything")
        XCTAssertTrue(chunks.isEmpty)
        let available = await client.isAvailable
        XCTAssertFalse(available)
    }

    func testSearchChunksReturnsEmptyOnMalformedJSON() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data("not json".utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "test-token", fetcher: mock)
        await client.probe()
        let chunks = await client.searchChunks(query: "anything")
        XCTAssertTrue(chunks.isEmpty)
    }

    // MARK: List books

    func testListBooksReturnsBooks() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/books"] = (Data(sampleBooksJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "test-token", fetcher: mock)
        await client.probe()
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

}
