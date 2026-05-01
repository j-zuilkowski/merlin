import XCTest
@testable import Merlin

@MainActor
final class RAGTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-rag-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    private func events(named name: String, in events: [[String: Any]]) -> [[String: Any]] {
        events.filter { $0["event"] as? String == name }
    }

    func testRAGSearchStartEmitted() async throws {
        let client = makeXcalibreClient(response: .chunksEmpty)

        _ = await client.searchChunks(
            query: "test query",
            source: "all",
            bookIDs: nil,
            projectPath: nil,
            limit: 5,
            rerank: false
        )

        let captured = try await capturedEvents()
        let starts = events(named: "rag.search.start", in: captured)
        XCTAssertFalse(starts.isEmpty, "rag.search.start not emitted")
        let d = starts[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["query_length"])
        XCTAssertNotNil(d?["limit"])
    }

    func testRAGSearchCompleteEmitted() async throws {
        let client = makeXcalibreClient(response: .chunksEmpty)

        _ = await client.searchChunks(
            query: "test query",
            source: "all",
            bookIDs: nil,
            projectPath: nil,
            limit: 5,
            rerank: false
        )

        let captured = try await capturedEvents()
        let completes = events(named: "rag.search.complete", in: captured)
        XCTAssertFalse(completes.isEmpty, "rag.search.complete not emitted")
        let ms = completes[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["result_count"])
    }

    func testRAGSearchErrorEmitted() async throws {
        let client = makeXcalibreClient(response: .networkError)

        _ = await client.searchChunks(
            query: "fail",
            source: "all",
            bookIDs: nil,
            projectPath: nil,
            limit: 5,
            rerank: false
        )

        let captured = try await capturedEvents()
        let errors = events(named: "rag.search.error", in: captured)
        XCTAssertFalse(errors.isEmpty, "rag.search.error not emitted on HTTP failure")
    }

    func testRAGMemoryWriteEmitted() async throws {
        let client = makeXcalibreClient(response: .writeSuccess)

        await client.writeMemoryChunk(
            content: "test memory content",
            title: "Test",
            projectPath: "/tmp/test",
            tags: []
        )

        let captured = try await capturedEvents()
        let writes = events(named: "rag.memory.write", in: captured)
        XCTAssertFalse(writes.isEmpty, "rag.memory.write not emitted")
        let d = writes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["chunk_bytes"])
    }
}

// MARK: - Helpers

private func makeXcalibreClient(response: MockRAGResponse = .chunksEmpty) -> XcalibreClient {
    let fetcher = MockRAGFetcher(response: response)
    return XcalibreClient(baseURL: "http://localhost:7777", fetcher: fetcher)
}

enum MockRAGResponse {
    case chunksEmpty
    case networkError
    case writeSuccess
}

final class MockRAGFetcher: HTTPFetching, @unchecked Sendable {
    let response: MockRAGResponse

    init(response: MockRAGResponse) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "http://localhost")!
        switch response {
        case .chunksEmpty:
            let body = "{\"chunks\":[]}".data(using: .utf8)!
            let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (body, r)
        case .networkError:
            throw URLError(.notConnectedToInternet)
        case .writeSuccess:
            let body = "{\"id\":\"abc123\"}".data(using: .utf8)!
            let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (body, r)
        }
    }
}
