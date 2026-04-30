import Foundation

// MARK: - GroundingReport

/// Per-turn summary of how well the model's response was grounded in retrieved context.
///
/// Emitted as `AgentEvent.groundingReport(_:)` after the RAG search step in every turn,
/// even when no chunks were retrieved (`totalChunks == 0`). This lets the UI and any
/// downstream telemetry distinguish between:
/// - Ungrounded turn (`totalChunks == 0`, `isWellGrounded == false`)
/// - Weakly grounded turn (chunks present but `averageScore < threshold`)
/// - Well-grounded turn (chunks present, `averageScore >= threshold`, no stale memory)
///
/// Addresses the "context degradation" failure pattern described in:
/// "Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"
/// https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems
///
/// `hasStaleMemory` and `oldestMemoryAgeDays` use `AppSettings.ragFreshnessThresholdDays`
/// as the freshness boundary. `isWellGrounded` uses `AppSettings.ragMinGroundingScore`.
struct GroundingReport: Sendable, Equatable {
    /// Total number of RAG chunks used to enrich the prompt (memory + book).
    let totalChunks: Int
    /// Number of chunks sourced from the local memory backend (`source == "memory"`).
    let memoryChunks: Int
    /// Number of chunks sourced from xcalibre book content (`source != "memory"`).
    let bookChunks: Int
    /// Mean score across all chunks. Zero when `totalChunks == 0`.
    /// For memory chunks: cosineScore from `MemorySearchResult.score`.
    /// For book chunks: `rrfScore` from `RAGChunk`.
    let averageScore: Double
    /// Age in days of the oldest memory chunk in the result set.
    /// `nil` when `memoryChunks == 0`.
    let oldestMemoryAgeDays: Int?
    /// `true` when at least one memory chunk is older than `AppSettings.ragFreshnessThresholdDays`.
    let hasStaleMemory: Bool
    /// `true` when `totalChunks > 0` and `averageScore >= AppSettings.ragMinGroundingScore`.
    let isWellGrounded: Bool

    /// Construct a `GroundingReport` from the merged RAG chunk list used in a turn.
    ///
    /// `memoryCreatedAts` carries the `createdAt` dates of any memory-sourced chunks
    /// because `RAGChunk` does not carry a creation timestamp. That information lives on
    /// `MemoryChunk` before conversion.
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
            if let cosineScore = chunk.cosineScore {
                return cosineScore
            }
            return chunk.rrfScore
        }
        let average = total > 0 ? scores.reduce(0, +) / Double(total) : 0

        let now = Date()
        let ageDays = memoryCreatedAts.map { created -> Int in
            Int(now.timeIntervalSince(created) / 86_400)
        }
        let oldestDays = ageDays.max()
        let stale = ageDays.contains { $0 > freshnessThresholdDays }
        let wellGrounded = total > 0 && average >= minGroundingScore

        return GroundingReport(
            totalChunks: total,
            memoryChunks: memCount,
            bookChunks: bookCount,
            averageScore: average,
            oldestMemoryAgeDays: oldestDays,
            hasStaleMemory: stale,
            isWellGrounded: wellGrounded
        )
    }
}
