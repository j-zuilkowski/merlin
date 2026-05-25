# Phase 108a — RAG Source Attribution Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 107b complete: skill frontmatter role/complexity declarations in place.

New surface introduced in phase 108b:
  - `AgentEvent.ragSources([RAGChunk])` — new event case emitted by runLoop when chunks are retrieved
  - `AgenticEngine` yields `.ragSources` immediately after chunks are found, before the enriched message is sent
  - `ChatViewModel` handles `.ragSources`: stores chunks as the most-recent turn's source list
  - `RAGSourcesView` — SwiftUI view rendering a collapsible "Sources" footer for an assistant bubble

TDD coverage:
  File 1 — RAGSourceAttributionTests: AgenticEngine emits .ragSources when chunks found, does not
            emit it when no chunks found; ChatViewModel stores latest sources; view type exists

---

## Write to: MerlinTests/Unit/RAGSourceAttributionTests.swift

```swift
import XCTest
@testable import Merlin

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
            toolRouter: ToolRouter(),
            contextManager: ContextManager(),
            xcalibreClient: xcalibre
        )

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "How do closures work?") {
            events.append(event)
        }

        let ragEvents = events.compactMap {
            if case .ragSources(let c) = $0 { return c } else { return nil }
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
            toolRouter: ToolRouter(),
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
            toolRouter: ToolRouter(),
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

private final class ScriptedProviderSA: LLMProvider, @unchecked Sendable {
    let id = "scripted-sa"
    let response: String
    init(response: String) { self.response = response }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: text, thinkingContent: nil, toolCalls: nil),
                finishReason: "stop"
            ))
            c.finish()
        }
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
Expected: BUILD FAILED — `AgentEvent.ragSources` not defined; `RAGSourcesView` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/RAGSourceAttributionTests.swift
git commit -m "Phase 108a — RAGSourceAttributionTests (failing)"
```
