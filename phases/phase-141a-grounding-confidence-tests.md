# Phase 141a — Grounding Confidence Signal Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 140b complete: circuit breaker in place. All prior tests pass.

Motivation (from production AI reliability analysis):
Context degradation is the failure mode where the model reasons over stale or incomplete
data in a way that is invisible to the user. The answer looks polished; the grounding is
gone. Adding a `GroundingReport` makes this visible per-turn — how many chunks backed
the answer, how confident the retrieval was, and whether memory chunks are stale.

New surface introduced in phase 141b:
  - `GroundingReport` struct — emitted after RAG search each turn:
      `totalChunks: Int`, `memoryChunks: Int`, `bookChunks: Int`,
      `averageScore: Double`, `oldestMemoryAgeDays: Int?`,
      `hasStaleMemory: Bool`, `isWellGrounded: Bool`
  - `AgentEvent.groundingReport(GroundingReport)` — new case on the existing enum.
  - `AppSettings.ragFreshnessThresholdDays: Int` — memory chunk age above which
    `hasStaleMemory` becomes true. TOML key: `rag_freshness_threshold_days`. Default: 90.
  - `AppSettings.ragMinGroundingScore: Double` — average score below which
    `isWellGrounded` is false. TOML key: `rag_min_grounding_score`. Default: 0.30.
  - The report is emitted even when `totalChunks == 0` (ungrounded turn),
    so downstream UI/telemetry can distinguish "no retrieval configured"
    from "retrieval ran but returned nothing."

TDD coverage:
  File: MerlinTests/Unit/GroundingConfidenceTests.swift
    - groundingReport event is emitted each turn
    - totalChunks is 0 when no RAG backend is configured
    - isWellGrounded is false when totalChunks is 0
    - memoryChunks counts only source=="memory" chunks
    - bookChunks counts only source!="memory" chunks
    - averageScore is mean of rrfScore/cosineScore across returned chunks
    - hasStaleMemory is true when a memory chunk's age exceeds threshold
    - hasStaleMemory is false when all memory chunks are fresh
    - isWellGrounded is false when averageScore < ragMinGroundingScore
    - isWellGrounded is true when chunks present and averageScore >= threshold
    - AppSettings.ragFreshnessThresholdDays defaults to 90
    - AppSettings.ragMinGroundingScore defaults to 0.30

---

## Write to: MerlinTests/Unit/GroundingConfidenceTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class GroundingConfidenceTests: XCTestCase {

    // MARK: - Helpers

    private func engine(backend: (any MemoryBackendPlugin)? = nil) -> AgenticEngine {
        AgenticEngine(
            provider: MockProvider(responses: ["ok"]),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager(),
            memoryBackend: backend ?? NullMemoryPlugin()
        )
    }

    private func groundingReport(from engine: AgenticEngine, message: String = "hello") async -> GroundingReport? {
        var report: GroundingReport?
        for await event in engine.send(message) {
            if case .groundingReport(let r) = event { report = r }
        }
        return report
    }

    // MARK: - Emission

    func testGroundingReportEmittedEachTurn() async throws {
        let e = engine()
        let report = await groundingReport(from: e)
        XCTAssertNotNil(report, "groundingReport event must be emitted every turn")
    }

    func testTotalChunksZeroWhenNoRAG() async throws {
        let e = engine()
        // No xcalibreClient, NullMemoryPlugin
        let report = await groundingReport(from: e)
        XCTAssertEqual(report?.totalChunks, 0)
    }

    func testIsWellGroundedFalseWhenNoChunks() async throws {
        let e = engine()
        let report = await groundingReport(from: e)
        XCTAssertEqual(report?.isWellGrounded, false)
    }

    // MARK: - Chunk counting

    func testMemoryChunksCountsOnlyMemorySource() async throws {
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "m1", content: "memory content", chunkType: "factual"),
                score: 0.8
            )
        ])
        let e = engine(backend: backend)
        let report = await groundingReport(from: e)
        XCTAssertEqual(report?.memoryChunks, 1)
        XCTAssertEqual(report?.bookChunks, 0)
    }

    func testTotalChunksIsSumOfMemoryAndBook() async throws {
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "m1", content: "mem", chunkType: "factual"),
                score: 0.75
            )
        ])
        let e = engine(backend: backend)
        let report = await groundingReport(from: e)
        // memory chunks + 0 book chunks
        XCTAssertEqual(report?.totalChunks, (report?.memoryChunks ?? 0) + (report?.bookChunks ?? 0))
    }

    // MARK: - Average score

    func testAverageScoreIsZeroWhenNoChunks() async throws {
        let e = engine()
        let report = await groundingReport(from: e)
        XCTAssertEqual(report?.averageScore ?? 0, 0, accuracy: 0.001)
    }

    func testAverageScoreComputedFromMemoryChunks() async throws {
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "m1", content: "a", chunkType: "factual"), score: 0.6),
            MemorySearchResult(
                chunk: MemoryChunk(id: "m2", content: "b", chunkType: "factual"), score: 0.8)
        ])
        let e = engine(backend: backend)
        let report = await groundingReport(from: e)
        // Expected average: (0.6 + 0.8) / 2 = 0.7
        XCTAssertEqual(report?.averageScore ?? 0, 0.7, accuracy: 0.01)
    }

    // MARK: - Staleness

    func testHasStaleMemoryTrueWhenChunkExceedsThreshold() async throws {
        AppSettings.shared.ragFreshnessThresholdDays = 30
        let oldDate = Calendar.current.date(byAdding: .day, value: -91, to: Date())!
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "old", content: "old content", chunkType: "factual",
                                   createdAt: oldDate),
                score: 0.7
            )
        ])
        let e = engine(backend: backend)
        let report = await groundingReport(from: e)
        XCTAssertEqual(report?.hasStaleMemory, true)
    }

    func testHasStaleMemoryFalseWhenAllChunksFresh() async throws {
        AppSettings.shared.ragFreshnessThresholdDays = 90
        let recentDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "fresh", content: "fresh content", chunkType: "factual",
                                   createdAt: recentDate),
                score: 0.8
            )
        ])
        let e = engine(backend: backend)
        let report = await groundingReport(from: e)
        XCTAssertEqual(report?.hasStaleMemory, false)
    }

    // MARK: - isWellGrounded

    func testIsWellGroundedFalseWhenBelowMinScore() async throws {
        AppSettings.shared.ragMinGroundingScore = 0.5
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "weak", content: "weak", chunkType: "factual"),
                score: 0.2  // below 0.5
            )
        ])
        let e = engine(backend: backend)
        let report = await groundingReport(from: e)
        XCTAssertEqual(report?.isWellGrounded, false)
    }

    func testIsWellGroundedTrueWhenChunksPresentAndScoreAboveThreshold() async throws {
        AppSettings.shared.ragMinGroundingScore = 0.3
        let backend = FixedSearchMemoryBackend(results: [
            MemorySearchResult(
                chunk: MemoryChunk(id: "good", content: "good content", chunkType: "factual"),
                score: 0.8
            )
        ])
        let e = engine(backend: backend)
        let report = await groundingReport(from: e)
        XCTAssertEqual(report?.isWellGrounded, true)
    }

    // MARK: - AppSettings defaults

    func testFreshnessThresholdDefaultIs90() {
        // Use a fresh-loaded instance to verify the default.
        XCTAssertEqual(AppSettings.shared.ragFreshnessThresholdDays, 90)
    }

    func testMinGroundingScoreDefaultIs0Point30() {
        XCTAssertEqual(AppSettings.shared.ragMinGroundingScore, 0.30, accuracy: 0.001)
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
Expected: BUILD FAILED — `GroundingReport`, `AgentEvent.groundingReport`,
`AppSettings.ragFreshnessThresholdDays`, `AppSettings.ragMinGroundingScore` undefined.

## Commit
```bash
git add MerlinTests/Unit/GroundingConfidenceTests.swift
git commit -m "Phase 141a — grounding confidence signal tests (failing)"
```
