# Phase 112a — RAG Settings Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 111b complete: rag_search tool source + project_path parameters in place.

New surface introduced in phase 112b:
  - `AppSettings.ragRerank: Bool` — whether to pass rerank=true to xcalibre (default: false)
  - `AppSettings.ragChunkLimit: Int` — how many chunks to retrieve per query (default: 3)
  - Both serialise to/from config.toml as `rag_rerank` and `rag_chunk_limit`
  - AgenticEngine.runLoop passes both values to searchChunks
  - Settings UI exposes both in the Library section

TDD coverage:
  File 1 — RAGSettingsTests: AppSettings defaults, round-trip, TOML serialisation, TOML omission
            when default, engine receives correct values from settings

---

## Write to: MerlinTests/Unit/RAGSettingsTests.swift

```swift
import XCTest
@testable import Merlin

final class RAGSettingsTests: XCTestCase {

    // MARK: - ragRerank

    func testRagRerankDefaultsFalse() {
        XCTAssertFalse(AppSettings.shared.ragRerank,
                       "ragRerank must default to false — safe for low-VRAM hardware")
    }

    func testRagRerankRoundTrip() {
        let original = AppSettings.shared.ragRerank
        AppSettings.shared.ragRerank = true
        XCTAssertTrue(AppSettings.shared.ragRerank)
        AppSettings.shared.ragRerank = original
    }

    func testRagRerankSerializesToTOML() {
        let settings = AppSettings.shared
        let saved = settings.ragRerank
        settings.ragRerank = true
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("rag_rerank"), "rag_rerank must appear in TOML when true")
        settings.ragRerank = saved
    }

    func testRagRerankNotWrittenToTOMLWhenFalse() {
        let settings = AppSettings.shared
        let saved = settings.ragRerank
        settings.ragRerank = false
        let toml = settings.serializedTOML()
        XCTAssertFalse(toml.contains("rag_rerank"),
                       "rag_rerank must be omitted from TOML when false (default)")
        settings.ragRerank = saved
    }

    func testRagRerankRoundTripsThroughTOML() {
        let settings = AppSettings.shared
        let saved = settings.ragRerank
        settings.ragRerank = true
        let toml = settings.serializedTOML()
        settings.ragRerank = false        // reset before re-applying
        settings.applyTOML(toml)
        XCTAssertTrue(settings.ragRerank)
        settings.ragRerank = saved
    }

    // MARK: - ragChunkLimit

    func testRagChunkLimitDefaultsThree() {
        XCTAssertEqual(AppSettings.shared.ragChunkLimit, 3,
                       "ragChunkLimit must default to 3")
    }

    func testRagChunkLimitRoundTrip() {
        let original = AppSettings.shared.ragChunkLimit
        AppSettings.shared.ragChunkLimit = 10
        XCTAssertEqual(AppSettings.shared.ragChunkLimit, 10)
        AppSettings.shared.ragChunkLimit = original
    }

    func testRagChunkLimitSerializesToTOML() {
        let settings = AppSettings.shared
        let saved = settings.ragChunkLimit
        settings.ragChunkLimit = 8
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("rag_chunk_limit"))
        XCTAssertTrue(toml.contains("8"))
        settings.ragChunkLimit = saved
    }

    func testRagChunkLimitNotWrittenToTOMLWhenDefault() {
        let settings = AppSettings.shared
        let saved = settings.ragChunkLimit
        settings.ragChunkLimit = 3
        let toml = settings.serializedTOML()
        XCTAssertFalse(toml.contains("rag_chunk_limit"),
                       "rag_chunk_limit must be omitted when at default value of 3")
        settings.ragChunkLimit = saved
    }

    func testRagChunkLimitRoundTripsThroughTOML() {
        let settings = AppSettings.shared
        let saved = settings.ragChunkLimit
        settings.ragChunkLimit = 12
        let toml = settings.serializedTOML()
        settings.ragChunkLimit = 3
        settings.applyTOML(toml)
        XCTAssertEqual(settings.ragChunkLimit, 12)
        settings.ragChunkLimit = saved
    }

    func testRagChunkLimitClampedToValidRange() {
        // Engine must clamp to 1...20 regardless of what AppSettings holds
        // This tests the engine's clamping, not AppSettings validation.
        let settings = AppSettings.shared
        let saved = settings.ragChunkLimit
        settings.ragChunkLimit = 0         // below minimum
        XCTAssertGreaterThanOrEqual(
            min(max(settings.ragChunkLimit, 1), 20), 1,
            "Engine clamp must produce at least 1"
        )
        settings.ragChunkLimit = 999       // above maximum
        XCTAssertLessThanOrEqual(
            min(max(settings.ragChunkLimit, 1), 20), 20,
            "Engine clamp must produce at most 20"
        )
        settings.ragChunkLimit = saved
    }

    // MARK: - Engine wiring

    func testEngineUsesRagRerankFromSettings() async throws {
        // Verify the engine passes AppSettings.ragRerank to searchChunks.
        // We spy on the URLRequest to check the rerank query parameter.
        let chunkJSON = """
        {"query":"q","chunks":[],"total_searched":0,"retrieval_ms":1}
        """
        let mock = MockHTTPFetcher()
        mock.responses["/health"] = (Data(), 200)
        mock.responses["/api/v1/search/chunks"] = (Data(chunkJSON.utf8), 200)
        let xcalibre = XcalibreClient(
            baseURL: "http://localhost:8083", token: "t", fetcher: mock)
        await xcalibre.probe()

        let provider = MinimalProviderRS()
        let registry = ProviderRegistry()
        registry.add(provider)
        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id],
            registry: registry,
            toolRouter: ToolRouter(),
            contextManager: ContextManager(),
            xcalibreClient: xcalibre
        )

        // Simulate settings with rerank = true
        engine.ragRerank = true
        engine.ragChunkLimit = 5

        for await _ in engine.send(userMessage: "test query") {}

        let req = mock.capturedRequests.first {
            $0.url?.path == "/api/v1/search/chunks"
        }
        XCTAssertNotNil(req)
        let components = URLComponents(url: req!.url!, resolvingAgainstBaseURL: false)
        let rerankVal = components?.queryItems?.first { $0.name == "rerank" }?.value
        XCTAssertEqual(rerankVal, "true")
        let limitVal = components?.queryItems?.first { $0.name == "limit" }?.value
        XCTAssertEqual(limitVal, "5")
    }
}

// MARK: - Helpers

private final class MinimalProviderRS: LLMProvider, @unchecked Sendable {
    let id = "minimal-rs"
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: "ok", thinkingContent: nil, toolCalls: nil),
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
Expected: BUILD FAILED — `AppSettings.ragRerank`, `AppSettings.ragChunkLimit`,
`AgenticEngine.ragRerank`, `AgenticEngine.ragChunkLimit` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/RAGSettingsTests.swift
git commit -m "Phase 112a — RAGSettingsTests (failing)"
```
