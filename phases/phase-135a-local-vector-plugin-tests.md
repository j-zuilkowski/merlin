# Phase 135a — LocalVectorPlugin Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 134b complete: MemoryBackendPlugin protocol, registry, NullMemoryPlugin in place.

New surface introduced in phase 135b:
  - `EmbeddingProviderProtocol` — Sendable protocol: `embed(_ text: String) async throws -> [Float]`,
    `var dimension: Int { get }`
  - `NLContextualEmbeddingProvider` — production implementation using NaturalLanguage.framework
  - `LocalVectorPlugin` — actor; MemoryBackendPlugin backed by SQLite + EmbeddingProviderProtocol
    - init(databasePath: String, embeddingProvider: any EmbeddingProviderProtocol)
    - SQLite schema created on first use: table `memory_chunks` with BLOB `embedding` column
    - write() stores chunk + embedding; search() loads embeddings + computes cosine similarity
    - delete() removes row by id

TDD coverage:
  File: MerlinTests/Unit/LocalVectorPluginTests.swift
    - pluginID is "local-vector"
    - write and search round-trip: written chunk appears in search results
    - delete removes chunk from search results
    - search returns at most topK results
    - search on empty store returns empty
    - search ranks more similar content higher
    - EmbeddingProviderProtocol conformance of MockEmbeddingProvider (compile-time)

  File: TestHelpers/MockEmbeddingProvider.swift
    - MockEmbeddingProvider: EmbeddingProviderProtocol
      dimension = 4
      embed() returns a deterministic [Float] based on text content
      (first 4 characters' normalized unicode scalar values)

---

## Write to: TestHelpers/MockEmbeddingProvider.swift

```swift
import Foundation
@testable import Merlin

/// Deterministic embedding provider for unit tests.
/// Returns a 4-dimensional vector derived from the first four Unicode scalar values of the
/// input text, normalised to [0, 1]. Two texts sharing a prefix will produce similar vectors,
/// which lets tests verify that cosine-similarity search ranks relevant content above noise.
struct MockEmbeddingProvider: EmbeddingProviderProtocol {
    let dimension: Int = 4

    func embed(_ text: String) async throws -> [Float] {
        var vector = [Float](repeating: 0, count: dimension)
        let scalars = Array(text.unicodeScalars.prefix(dimension))
        for (i, scalar) in scalars.enumerated() {
            vector[i] = Float(scalar.value) / 128.0
        }
        return vector
    }
}
```

---

## Write to: MerlinTests/Unit/LocalVectorPluginTests.swift

```swift
import XCTest
@testable import Merlin

final class LocalVectorPluginTests: XCTestCase {

    private func makePlugin() -> LocalVectorPlugin {
        let dbPath = "/tmp/merlin-test-vector-\(UUID().uuidString).sqlite"
        return LocalVectorPlugin(databasePath: dbPath, embeddingProvider: MockEmbeddingProvider())
    }

    func testPluginIDIsLocalVector() {
        let plugin = makePlugin()
        XCTAssertEqual(plugin.pluginID, "local-vector")
    }

    func testWriteAndSearchRoundTrip() async throws {
        let plugin = makePlugin()
        let chunk = MemoryChunk(id: "c1", content: "apple banana cherry",
                                chunkType: "episodic")
        try await plugin.write(chunk)

        let results = try await plugin.search(query: "apple banana cherry", topK: 5)
        XCTAssertFalse(results.isEmpty, "Written chunk should appear in search results")
        XCTAssertEqual(results.first?.chunk.id, "c1")
    }

    func testDeleteRemovesChunk() async throws {
        let plugin = makePlugin()
        let chunk = MemoryChunk(id: "d1", content: "delete me", chunkType: "factual")
        try await plugin.write(chunk)
        try await plugin.delete(id: "d1")

        let results = try await plugin.search(query: "delete me", topK: 5)
        XCTAssertTrue(results.allSatisfy { $0.chunk.id != "d1" })
    }

    func testSearchReturnsAtMostTopK() async throws {
        let plugin = makePlugin()
        for i in 0..<10 {
            let chunk = MemoryChunk(id: "t\(i)", content: "abc content \(i)",
                                    chunkType: "episodic")
            try await plugin.write(chunk)
        }
        let results = try await plugin.search(query: "abc content", topK: 3)
        XCTAssertLessThanOrEqual(results.count, 3)
    }

    func testSearchOnEmptyStoreReturnsEmpty() async throws {
        let plugin = makePlugin()
        let results = try await plugin.search(query: "anything", topK: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchRanksRelevantContentHigher() async throws {
        let plugin = makePlugin()
        // "aaa..." has a very different embedding from "zzz..."
        let relevant = MemoryChunk(id: "rel", content: "aardvark antelope",
                                   chunkType: "episodic")
        let noise = MemoryChunk(id: "noise", content: "zzz zzz zzz",
                                chunkType: "episodic")
        try await plugin.write(relevant)
        try await plugin.write(noise)

        let results = try await plugin.search(query: "aardvark antelope", topK: 2)
        XCTAssertEqual(results.first?.chunk.id, "rel",
                       "More similar chunk should rank first")
    }

    func testSearchResultScoresAreInDescendingOrder() async throws {
        let plugin = makePlugin()
        for i in 0..<5 {
            let chunk = MemoryChunk(id: "s\(i)", content: "item \(i)",
                                    chunkType: "episodic")
            try await plugin.write(chunk)
        }
        let results = try await plugin.search(query: "item 0", topK: 5)
        let scores = results.map { $0.score }
        XCTAssertEqual(scores, scores.sorted(by: >), "Results must be sorted descending by score")
    }

    func testMockEmbeddingProviderConformsToProtocol() {
        let _: any EmbeddingProviderProtocol = MockEmbeddingProvider()
    }
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
Expected: BUILD FAILED — `EmbeddingProviderProtocol`, `LocalVectorPlugin` are undefined.

## Commit
```bash
git add MerlinTests/Unit/LocalVectorPluginTests.swift
git add TestHelpers/MockEmbeddingProvider.swift
git commit -m "Phase 135a — LocalVectorPlugin tests (failing)"
```
