import XCTest
@testable import Merlin

final class MemoryBrowserTests: XCTestCase {

    private let memoryChunkJSON = """
    {
        "query": "login",
        "chunks": [{
            "chunk_id": "m1", "source": "memory",
            "book_id": null, "book_title": null,
            "heading_path": null, "chunk_type": "episodic",
            "text": "Implemented OAuth login flow.", "word_count": 4,
            "bm25_score": null, "cosine_score": null,
            "rrf_score": 0.8, "rerank_score": null
        }],
        "total_searched": 50, "retrieval_ms": 3
    }
    """

    // MARK: - searchMemory sends source=memory

    func testSearchMemoryPassesSourceMemory() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(memoryChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await client.searchMemory(query: "login", projectPath: nil as String?, limit: 10)

        let searchReq = mock.capturedRequests.first {
            $0.url?.path == "/api/v1/search/chunks"
        }
        XCTAssertNotNil(searchReq, "searchMemory must hit /api/v1/search/chunks")
        let components = URLComponents(url: searchReq!.url!, resolvingAgainstBaseURL: false)
        let sourceItem = components?.queryItems?.first { $0.name == "source" }
        XCTAssertEqual(sourceItem?.value, "memory",
                       "source must be 'memory' in the request URL")
    }

    func testSearchMemoryPassesProjectPath() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(memoryChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await client.searchMemory(query: "auth", projectPath: "/opt/project", limit: 5)

        let searchReq = mock.capturedRequests.first {
            $0.url?.path == "/api/v1/search/chunks"
        }!
        let components = URLComponents(url: searchReq.url!, resolvingAgainstBaseURL: false)
        let pathItem = components?.queryItems?.first { $0.name == "project_path" }
        XCTAssertEqual(pathItem?.value, "/opt/project")
    }

    func testSearchMemoryReturnsChunksWithSourceMemory() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(memoryChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        let chunks = await client.searchMemory(query: "login", projectPath: nil as String?, limit: 10)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].source, "memory")
        XCTAssertEqual(chunks[0].chunkType, "episodic")
    }

    func testSearchMemoryReturnsEmptyWhenUnavailable() async {
        let mock = MockHTTPFetcher() // no /health → stays unavailable
        let client = XcalibreClient(baseURL: "http://localhost:8083", fetcher: mock)
        let chunks = await client.searchMemory(query: "anything", projectPath: nil as String?, limit: 10)
        XCTAssertTrue(chunks.isEmpty)
    }

    func testSearchMemoryClampsLimitTo100() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(memoryChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await client.searchMemory(query: "q", projectPath: nil as String?, limit: 9999)

        let searchReq = mock.capturedRequests.first {
            $0.url?.path == "/api/v1/search/chunks"
        }!
        let components = URLComponents(url: searchReq.url!, resolvingAgainstBaseURL: false)
        let limitItem = components?.queryItems?.first { $0.name == "limit" }
        let limit = Int(limitItem?.value ?? "0") ?? 0
        XCTAssertLessThanOrEqual(limit, 100, "searchMemory limit must be clamped to 100")
    }

    // MARK: - View type existence

    @MainActor
    func testMemoryBrowserViewTypeExists() {
        guard ProcessInfo.processInfo.environment["RUN_VIEW_INSTANTIATION"] == "1" else { return }
        _ = MemoryBrowserView()
    }
}
