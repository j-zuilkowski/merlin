# Phase 111a — rag_search Tool Source/ProjectPath Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 110b complete: memory browser in place.

New surface introduced in phase 111b:
  - `RAGTools.search(args:client:projectPath:)` gains an optional `projectPath` parameter
    so the tool handler can scope searches to the active project
  - `RAGTools.Args` struct gains `source: String?` and `projectPath: String?` decoded from tool args
  - `ToolDefinitions.ragSearch` schema updated to document `source` ("books"/"memory"/"all") and
    `project_path` optional parameters
  - AppState wires `projectPath` from AppSettings into the `rag_search` tool handler registration

TDD coverage:
  File 1 — RAGSearchToolTests: source param forwarded correctly (books/memory/all);
            projectPath forwarded; defaults to source="books" when omitted;
            limit still clamped to 20

---

## Write to: MerlinTests/Unit/RAGSearchToolTests.swift

```swift
import XCTest
@testable import Merlin

final class RAGSearchToolTests: XCTestCase {

    private let singleChunkJSON = """
    {
        "query": "test", "chunks": [{
            "chunk_id": "c1", "source": "books",
            "book_id": "b1", "book_title": "Swift Book",
            "heading_path": "Chapter 1", "chunk_type": "paragraph",
            "text": "Some text.", "word_count": 2,
            "bm25_score": 0.8, "cosine_score": 0.7,
            "rrf_score": 0.9, "rerank_score": null
        }],
        "total_searched": 5, "retrieval_ms": 2
    }
    """

    // MARK: - source parameter forwarding

    func testSearchDefaultsToSourceBooks() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(singleChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await RAGTools.search(args: #"{"query":"test"}"#, client: client, projectPath: nil)

        let req = mock.capturedRequests.first { $0.url?.path == "/api/v1/search/chunks" }!
        let components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        let sourceVal = components?.queryItems?.first { $0.name == "source" }?.value
        XCTAssertEqual(sourceVal, "books", "rag_search must default source to 'books'")
    }

    func testSearchForwardsSourceMemory() async throws {
        let memoryJSON = singleChunkJSON.replacingOccurrences(of: "\"books\"", with: "\"memory\"")
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(memoryJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await RAGTools.search(
            args: #"{"query":"test","source":"memory"}"#,
            client: client,
            projectPath: nil
        )

        let req = mock.capturedRequests.first { $0.url?.path == "/api/v1/search/chunks" }!
        let components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        let sourceVal = components?.queryItems?.first { $0.name == "source" }?.value
        XCTAssertEqual(sourceVal, "memory")
    }

    func testSearchForwardsSourceAll() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(singleChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await RAGTools.search(
            args: #"{"query":"test","source":"all"}"#,
            client: client,
            projectPath: nil
        )

        let req = mock.capturedRequests.first { $0.url?.path == "/api/v1/search/chunks" }!
        let components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        let sourceVal = components?.queryItems?.first { $0.name == "source" }?.value
        XCTAssertEqual(sourceVal, "all")
    }

    // MARK: - projectPath forwarding

    func testSearchForwardsProjectPathFromArgs() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(singleChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await RAGTools.search(
            args: #"{"query":"test","project_path":"/opt/proj"}"#,
            client: client,
            projectPath: nil
        )

        let req = mock.capturedRequests.first { $0.url?.path == "/api/v1/search/chunks" }!
        let components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        let pathVal = components?.queryItems?.first { $0.name == "project_path" }?.value
        XCTAssertEqual(pathVal, "/opt/proj")
    }

    func testSearchFallsBackToEngineProjectPath() async throws {
        // When args don't include project_path, the handler's `projectPath` parameter is used.
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(singleChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await RAGTools.search(
            args: #"{"query":"test"}"#,
            client: client,
            projectPath: "/engine/path"
        )

        let req = mock.capturedRequests.first { $0.url?.path == "/api/v1/search/chunks" }!
        let components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        let pathVal = components?.queryItems?.first { $0.name == "project_path" }?.value
        XCTAssertEqual(pathVal, "/engine/path")
    }

    // MARK: - limit still clamped

    func testSearchStillClampsLimitTo20() async throws {
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(singleChunkJSON.utf8), 200)
        let client = XcalibreClient(baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await client.probe()

        _ = await RAGTools.search(
            args: #"{"query":"test","limit":500}"#,
            client: client,
            projectPath: nil
        )

        let req = mock.capturedRequests.first { $0.url?.path == "/api/v1/search/chunks" }!
        let components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        let limitVal = Int(components?.queryItems?.first { $0.name == "limit" }?.value ?? "0")!
        XCTAssertLessThanOrEqual(limitVal, 20)
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `RAGTools.search(args:client:projectPath:)` signature mismatch
(currently has no `projectPath` parameter); `RAGTools.Args.source` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/RAGSearchToolTests.swift
git commit -m "Phase 111a — RAGSearchToolTests (failing)"
```
