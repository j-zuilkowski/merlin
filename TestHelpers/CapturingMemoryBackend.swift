import Foundation
@testable import Merlin

/// Test double that records every chunk passed to `write(_:)`.
/// Used to assert that engines write correct chunks without a real database.
actor CapturingMemoryBackend: MemoryBackendPlugin {
    nonisolated let pluginID = "capturing"
    nonisolated let displayName = "Capturing (test)"

    private(set) var writtenChunks: [MemoryChunk] = []

    func write(_ chunk: MemoryChunk) async throws {
        writtenChunks.append(chunk)
    }

    func search(query: String, topK: Int) async throws -> [MemorySearchResult] { [] }

    func delete(id: String) async throws {}
}
