# Phase 137a — AgenticEngine Memory Plugin Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 136b complete: MemoryEngine uses MemoryBackendPlugin for approved memory writes.

New surface introduced in phase 137b:
  - `AgenticEngine.setMemoryBackend(_ backend: any MemoryBackendPlugin)` — replaces the
    xcalibre episodic write at session end. The xcalibre client is KEPT for book-content
    RAG search (`source: "all"`). Only the memory write is redirected.
  - RAG enrichment now merges results from two sources:
      1. Local memory search (from `memoryBackend.search(query:topK:)`)
      2. xcalibre book search (from `xcalibreClient.searchChunks(...)`, unchanged)
    Both sets are converted to `RAGChunk` and passed to `RAGTools.buildEnrichedMessage`.
  - The critic-gated suppression logic is preserved: a `.fail` verdict from the critic
    still suppresses the episodic write to the backend.

TDD coverage:
  File: MerlinTests/Unit/AgenticEngineMemoryPluginTests.swift
    - setMemoryBackend injects backend (compile-time)
    - episodic write goes to backend not xcalibre after a completed turn
    - critic fail suppresses backend write
    - critic pass (or nil) allows backend write
    - memory search results appear in RAG context when backend returns chunks
    - xcalibre book search still fires when xcalibreClient is set

---

## Write to: MerlinTests/Unit/AgenticEngineMemoryPluginTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineMemoryPluginTests: XCTestCase {

    // MARK: - Helpers

    private func makeEngine(
        provider: MockProvider = MockProvider(responses: ["ok"]),
        backend: CapturingMemoryBackend = CapturingMemoryBackend()
    ) -> (AgenticEngine, CapturingMemoryBackend) {
        let engine = AgenticEngine(
            provider: provider,
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager(),
            memoryBackend: backend
        )
        return (engine, backend)
    }

    // MARK: - Injection

    func testSetMemoryBackendCompiles() {
        let engine = AgenticEngine(
            provider: MockProvider(responses: ["hi"]),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager()
        )
        // If AgenticEngine.init accepts memoryBackend: parameter OR setMemoryBackend exists,
        // this test passes at compile time.
        engine.setMemoryBackend(NullMemoryPlugin())
    }

    // MARK: - Episodic write

    func testEpisodicWriteGoesToBackendAfterTurn() async throws {
        let backend = CapturingMemoryBackend()
        let (engine, _) = makeEngine(
            provider: MockProvider(responses: ["Here is my response."]),
            backend: backend
        )
        await AppSettings.shared.setMemoriesEnabled(true)

        var events: [AgentEvent] = []
        for await event in engine.send("Hello") {
            events.append(event)
        }

        let written = await backend.writtenChunks
        XCTAssertFalse(written.isEmpty, "Episodic chunk should have been written after turn")
        XCTAssertEqual(written.first?.chunkType, "episodic")
    }

    func testCriticFailSuppressesBackendWrite() async throws {
        let backend = CapturingMemoryBackend()
        let failCritic = AlwaysFailCritic()
        let (engine, _) = makeEngine(backend: backend)
        engine.criticOverride = failCritic
        await AppSettings.shared.setMemoriesEnabled(true)

        for await _ in engine.send("Test") {}

        let written = await backend.writtenChunks
        XCTAssertTrue(written.isEmpty, "Critic .fail should suppress episodic write")
    }

    func testCriticPassAllowsBackendWrite() async throws {
        let backend = CapturingMemoryBackend()
        let passCritic = AlwaysPassCritic()
        let (engine, _) = makeEngine(backend: backend)
        engine.criticOverride = passCritic
        await AppSettings.shared.setMemoriesEnabled(true)

        for await _ in engine.send("Test") {}

        let written = await backend.writtenChunks
        XCTAssertFalse(written.isEmpty, "Critic .pass should allow episodic write")
    }

    // MARK: - RAG search

    func testMemorySearchResultsAppearsInRAGSources() async throws {
        let backend = CapturingMemoryBackend()
        // Prime backend with a searchable chunk by using a LocalVectorPlugin stub
        // that returns a fixed result when queried.
        let searchingBackend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "m1", content: "user prefers dark mode",
                                   chunkType: "factual"),
                score: 0.9
            )
        ])
        let engine = AgenticEngine(
            provider: MockProvider(responses: ["ok"]),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager(),
            memoryBackend: searchingBackend
        )

        var ragSourceEvents: [AgentEvent] = []
        for await event in engine.send("What display mode does the user prefer?") {
            if case .ragSources = event {
                ragSourceEvents.append(event)
            }
        }

        XCTAssertFalse(ragSourceEvents.isEmpty,
                       "RAG sources event should fire when memory backend returns results")
    }
}

// MARK: - Test doubles

/// Memory backend that always returns a fixed set of search results.
actor FixedSearchMemoryBackend: MemoryBackendPlugin {
    nonisolated let pluginID = "fixed-search"
    nonisolated let displayName = "Fixed search (test)"
    private let results: [MemorySearchResult]

    init(results: [MemorySearchResult]) { self.results = results }

    func write(_ chunk: MemoryChunk) async throws {}
    func search(query: String, topK: Int) async throws -> [MemorySearchResult] {
        Array(results.prefix(topK))
    }
    func delete(id: String) async throws {}
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `AgenticEngine.init` does not yet accept `memoryBackend:` parameter
and `setMemoryBackend(_:)` does not exist.

## Commit
```bash
git add MerlinTests/Unit/AgenticEngineMemoryPluginTests.swift
git commit -m "Phase 137a — AgenticEngine memory plugin tests (failing)"
```
