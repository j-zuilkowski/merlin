# Phase 141b — Grounding Confidence Signal Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 141a complete: failing tests for grounding confidence signal in place.

---

## Write to: Merlin/Engine/GroundingReport.swift

```swift
import Foundation

// MARK: - GroundingReport

/// Per-turn summary of how well the model's response was grounded in retrieved context.
///
/// Emitted as `AgentEvent.groundingReport(_:)` after the RAG search step in every turn,
/// even when no chunks were retrieved (`totalChunks == 0`). This lets the UI and any
/// downstream telemetry distinguish between:
///   - Ungrounded turn (totalChunks == 0, isWellGrounded == false)
///   - Weakly grounded turn (chunks present but averageScore < threshold)
///   - Well-grounded turn (chunks present, averageScore >= threshold, no stale memory)
///
/// Addresses the "context degradation" failure pattern — a system reasoning over stale
/// or incomplete data in a way invisible to the user — described in:
/// "Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"
/// https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems
///
/// `hasStaleMemory` and `oldestMemoryAgeDays` use `AppSettings.ragFreshnessThresholdDays`
/// as the freshness boundary. `isWellGrounded` uses `AppSettings.ragMinGroundingScore`.
struct GroundingReport: Sendable {
    /// Total number of RAG chunks used to enrich the prompt (memory + book).
    let totalChunks: Int
    /// Number of chunks sourced from the local memory backend (source == "memory").
    let memoryChunks: Int
    /// Number of chunks sourced from xcalibre book content (source != "memory").
    let bookChunks: Int
    /// Mean score across all chunks. 0 when `totalChunks == 0`.
    /// For memory chunks: cosineScore (from MemorySearchResult.score).
    /// For book chunks: rrfScore from RAGChunk.
    let averageScore: Double
    /// Age in days of the oldest memory chunk in the result set.
    /// nil when `memoryChunks == 0`.
    let oldestMemoryAgeDays: Int?
    /// True when at least one memory chunk is older than `AppSettings.ragFreshnessThresholdDays`.
    let hasStaleMemory: Bool
    /// True when `totalChunks > 0` AND `averageScore >= AppSettings.ragMinGroundingScore`.
    let isWellGrounded: Bool

    /// Construct a GroundingReport from the merged RAG chunk list used in a turn.
    ///
    /// `memoryCreatedAts` carries the `createdAt` dates of any memory-sourced chunks
    /// (keyed separately because RAGChunk does not carry a creation timestamp — that
    /// information lives on `MemoryChunk` before conversion).
    static func build(
        ragChunks: [RAGChunk],
        memoryCreatedAts: [Date],
        freshnessThresholdDays: Int,
        minGroundingScore: Double
    ) -> GroundingReport {
        let total = ragChunks.count
        let memCount = ragChunks.filter { $0.source == "memory" }.count
        let bookCount = total - memCount

        let scores = ragChunks.map { chunk -> Double in
            if let cos = chunk.cosineScore { return cos }
            return chunk.rrfScore
        }
        let avg = total > 0 ? scores.reduce(0, +) / Double(total) : 0.0

        let now = Date()
        let ageDays = memoryCreatedAts.map { created -> Int in
            Int(now.timeIntervalSince(created) / 86400)
        }
        let oldestDays = ageDays.max()
        let threshold = freshnessThresholdDays
        let stale = ageDays.contains { $0 > threshold }

        let wellGrounded = total > 0 && avg >= minGroundingScore

        return GroundingReport(
            totalChunks: total,
            memoryChunks: memCount,
            bookChunks: bookCount,
            averageScore: avg,
            oldestMemoryAgeDays: oldestDays,
            hasStaleMemory: stale,
            isWellGrounded: wellGrounded
        )
    }
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1 — Add groundingReport case to AgentEvent

```swift
enum AgentEvent {
    case text(String)
    case thinking(String)
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case subagentStarted(id: UUID, agentName: String)
    case subagentUpdate(id: UUID, event: SubagentEvent)
    case systemNote(String)
    case ragSources([RAGChunk])
    /// Per-turn grounding confidence report. Emitted after RAG search even when
    /// totalChunks == 0, so callers can distinguish ungrounded from well-grounded turns.
    case groundingReport(GroundingReport)
    case error(Error)
}
```

### 2 — Update AppSettings.swift: add freshness + grounding score settings

In `Merlin/Config/AppSettings.swift`, add alongside existing RAG settings:

```swift
/// TOML key: `rag_freshness_threshold_days`.
/// Memory chunks older than this many days are flagged as stale in GroundingReport.
/// Default: 90 days.
@Published var ragFreshnessThresholdDays: Int = 90

/// TOML key: `rag_min_grounding_score`.
/// Average RAG score below this threshold causes `GroundingReport.isWellGrounded` to
/// be false even when chunks were returned. Default: 0.30.
@Published var ragMinGroundingScore: Double = 0.30
```

Add to the TOML CodingKeys enum:
```swift
case ragFreshnessThresholdDays = "rag_freshness_threshold_days"
case ragMinGroundingScore = "rag_min_grounding_score"
```

Add to load method:
```swift
if let value = config.ragFreshnessThresholdDays { ragFreshnessThresholdDays = value }
if let value = config.ragMinGroundingScore { ragMinGroundingScore = value }
```

Add to save method (non-default values only):
```swift
if ragFreshnessThresholdDays != 90 {
    lines.append("rag_freshness_threshold_days = \(ragFreshnessThresholdDays)")
}
if abs(ragMinGroundingScore - 0.30) > 0.001 {
    lines.append("rag_min_grounding_score = \(ragMinGroundingScore)")
}
```

### 3 — Update runLoop: emit GroundingReport after RAG search

Locate the RAG enrichment block (the one updated in phase 137b). After the block that
populates `ragChunks` (both memory + xcalibre search), before returning to the main
turn logic, add:

```swift
// Collect createdAt dates from memory-sourced results (needed for freshness check).
// Memory search results carry MemoryChunk.createdAt; book chunks do not have a
// creation timestamp so only memory chunks contribute to staleness detection.
let memoryDates: [Date]
if let memResults = try? await memoryBackend.search(query: userMessage, topK: 5) {
    memoryDates = memResults.map { $0.chunk.createdAt }
} else {
    memoryDates = []
}

let freshnessThreshold = await MainActor.run { AppSettings.shared.ragFreshnessThresholdDays }
let minScore = await MainActor.run { AppSettings.shared.ragMinGroundingScore }
let report = GroundingReport.build(
    ragChunks: ragChunks,
    memoryCreatedAts: memoryDates,
    freshnessThresholdDays: freshnessThreshold,
    minGroundingScore: minScore
)
continuation.yield(.groundingReport(report))
```

NOTE: The memory search above is the second call to `memoryBackend.search` in the turn
(the first happened in the existing RAG block). To avoid the double call, refactor: capture
the `MemorySearchResult` array from the first call and pass it both to `ragChunks` assembly
AND to `GroundingReport.build`. The phase file shows the intent; Codex should refactor to
avoid the redundant search call, e.g.:

```swift
// Single memory search — result used for both RAG enrichment and grounding report.
let memResults = (try? await memoryBackend.search(query: userMessage, topK: 5)) ?? []
let memRagChunks = memResults.map { $0.toRAGChunk() }
let memoryDates = memResults.map { $0.chunk.createdAt }

// xcalibre book search (optional)
var bookChunks: [RAGChunk] = []
if let client = xcalibreClient {
    bookChunks = await client.searchChunks(...)
}

let ragChunks = memRagChunks + bookChunks

// Enrich message
if !ragChunks.isEmpty {
    effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: ragChunks)
    continuation.yield(.ragSources(ragChunks))
}

// Grounding report — always emit, even when ragChunks is empty.
let freshnessThreshold = await MainActor.run { AppSettings.shared.ragFreshnessThresholdDays }
let minScore = await MainActor.run { AppSettings.shared.ragMinGroundingScore }
continuation.yield(.groundingReport(GroundingReport.build(
    ragChunks: ragChunks,
    memoryCreatedAts: memoryDates,
    freshnessThresholdDays: freshnessThreshold,
    minGroundingScore: minScore
)))
```

---

## Handle new AgentEvent case in existing UI event consumers

Search for `switch event` or `for await event` patterns in the UI layer that handle
`AgentEvent`. Add a handler for `.groundingReport` that stores the report on the
session or view model for display. At minimum, add a no-op case so exhaustive switches
don't fail to compile:

```swift
case .groundingReport:
    break  // stored/displayed by the view layer in a future phase
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED — all 141a tests pass, zero warnings.

If exhaustive switch errors appear in the UI layer for the new `.groundingReport` case,
add `case .groundingReport: break` to each switch site.

## Commit
```bash
git add Merlin/Engine/GroundingReport.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/Config/AppSettings.swift
git commit -m "Phase 141b — GroundingReport: per-turn grounding confidence signal"
```
