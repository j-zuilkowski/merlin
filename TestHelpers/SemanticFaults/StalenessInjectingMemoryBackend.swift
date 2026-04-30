import Foundation
@testable import Merlin

/// Memory backend that returns results with a configurable `createdAt` age.
/// Used in semantic fault injection tests to simulate a retrieval store
/// that has not received new writes and is returning stale context.
actor StalenessInjectingMemoryBackend: MemoryBackendPlugin {
    nonisolated let pluginID = "stale-injecting"
    nonisolated let displayName = "Stale Injecting (test)"

    /// Age in days to assign to all returned chunks. Default 91 — exceeds the default
    /// ragFreshnessThresholdDays of 90 so hasStaleMemory fires by default.
    let ageDays: Int
    let content: String

    init(ageDays: Int = 91, content: String = "stale memory content") {
        self.ageDays = ageDays
        self.content = content
    }

    func write(_ chunk: MemoryChunk) async throws {}

    func search(query: String, topK: Int) async throws -> [MemorySearchResult] {
        let staleDate = Calendar.current.date(
            byAdding: .day,
            value: -ageDays,
            to: Date()
        ) ?? Date()
        let chunk = MemoryChunk(
            id: UUID().uuidString,
            content: content,
            chunkType: "factual",
            createdAt: staleDate
        )
        return [MemorySearchResult(chunk: chunk, score: 0.75)]
    }

    func delete(id: String) async throws {}
}
