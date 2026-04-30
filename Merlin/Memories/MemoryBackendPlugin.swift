import Foundation

// MARK: - MemoryChunk

/// A single stored memory record.
///
/// Merlin uses this one type for two cases:
/// - approved factual memories from the Memory Review flow
/// - episodic summaries written automatically at the end of an agentic turn
///
/// All fields except `id`, `content`, and `chunkType` are optional so both cases can
/// share the same storage schema.
struct MemoryChunk: Sendable, Equatable {
    /// Stable UUID string assigned at creation time.
    let id: String
    /// The text content of the memory.
    let content: String
    /// Semantic category: "factual" for approved memories, "episodic" for auto-summaries.
    let chunkType: String
    /// Optional labels for filtering (e.g. ["session-memory"]).
    let tags: [String]
    /// ID of the session that produced this chunk, if known.
    let sessionID: String?
    /// File-system project path active when this chunk was written, if known.
    let projectPath: String?
    /// Creation timestamp — set to Date() at write time.
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        content: String,
        chunkType: String,
        tags: [String] = [],
        sessionID: String? = nil,
        projectPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.chunkType = chunkType
        self.tags = tags
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.createdAt = createdAt
    }
}

// MARK: - MemorySearchResult

/// A search result returned by `MemoryBackendPlugin.search(query:topK:)`.
/// `score` is cosine similarity in `[0, 1]`, where higher values are more relevant.
struct MemorySearchResult: Sendable {
    let chunk: MemoryChunk
    /// Cosine similarity score in [0, 1].
    let score: Float

    /// Converts this result into a `RAGChunk` for the RAG enrichment pipeline.
    /// `source` is set to `"memory"` so the UI can distinguish memory chunks from book chunks.
    /// `bm25Score` stays nil because the row was ranked by embeddings, while `cosineScore`
    /// and `rrfScore` both carry the similarity score that produced the ranking.
    func toRAGChunk() -> RAGChunk {
        RAGChunk(
            chunkID: chunk.id,
            source: "memory",
            bookID: nil,
            bookTitle: nil,
            headingPath: nil,
            chunkType: chunk.chunkType,
            text: chunk.content,
            wordCount: nil,
            bm25Score: nil,
            cosineScore: Double(score),
            rrfScore: Double(score),
            rerankScore: nil
        )
    }
}

// MARK: - MemoryBackendPlugin

/// Protocol for all memory storage backends.
///
/// Built-in implementations:
/// - `NullMemoryPlugin` (`"null"`) — no-op default while the app is still wiring settings.
/// - `LocalVectorPlugin` (`"local-vector"`) — SQLite + `NLContextualEmbedding` production backend.
///
/// Conforming types are actors so storage operations are serialized. `pluginID` and
/// `displayName` are `nonisolated` so the registry can read them without an `await`.
protocol MemoryBackendPlugin: Actor {
    /// Stable identifier used to persist the active plugin choice in AppSettings.
    nonisolated var pluginID: String { get }
    /// Human-readable name shown in Settings.
    nonisolated var displayName: String { get }

    /// Persist a memory chunk. Implementations should embed the content asynchronously
    /// if embedding is expensive, so this call returns quickly.
    func write(_ chunk: MemoryChunk) async throws

    /// Return up to `topK` chunks most relevant to `query`, sorted descending by score.
    func search(query: String, topK: Int) async throws -> [MemorySearchResult]

    /// Remove the chunk with `id`. Silent no-op if not found.
    func delete(id: String) async throws
}

// MARK: - NullMemoryPlugin

/// No-op memory backend.
///
/// AppState uses this before the real backend is wired, and tests use it when they only
/// care that memory calls are safe to make.
actor NullMemoryPlugin: MemoryBackendPlugin {
    nonisolated let pluginID = "null"
    nonisolated let displayName = "None"

    func write(_ chunk: MemoryChunk) async throws {}
    func search(query: String, topK: Int) async throws -> [MemorySearchResult] { [] }
    func delete(id: String) async throws {}
}

// MARK: - MemoryBackendRegistry

/// Maintains the set of registered `MemoryBackendPlugin` implementations and tracks
/// which one is currently active.
///
/// `AppState` owns one registry, registers the built-in plugins at init, then selects
/// the active plugin from `AppSettings.memoryBackendID` before injecting it into the
/// engines.
@MainActor
final class MemoryBackendRegistry {
    private var plugins: [String: any MemoryBackendPlugin] = [:]
    /// ID of the currently active plugin. Defaults to "null" until a plugin is registered
    /// and set active.
    private(set) var activePluginID: String = "null"

    init() {
        // Register the null plugin so activePlugin always returns a valid value.
        let null = NullMemoryPlugin()
        plugins[null.pluginID] = null
    }

    /// Add a plugin to the registry without changing the active plugin.
    func register(_ plugin: any MemoryBackendPlugin) {
        plugins[plugin.pluginID] = plugin
    }

    /// Set the active plugin by ID. Unknown IDs are ignored so the current selection stays valid.
    func setActive(pluginID: String) {
        guard plugins[pluginID] != nil else { return }
        activePluginID = pluginID
    }

    /// The currently active plugin. Falls back to `NullMemoryPlugin` if the stored ID
    /// is not present in the registry.
    var activePlugin: any MemoryBackendPlugin {
        plugins[activePluginID] ?? NullMemoryPlugin()
    }
}
