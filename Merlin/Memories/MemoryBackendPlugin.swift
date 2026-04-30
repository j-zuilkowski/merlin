import Foundation

// MARK: - MemoryChunk

/// A single stored memory record — the on-disk unit written by MemoryEngine.approve()
/// and the episodic summaries written by AgenticEngine at session end.
///
/// All fields except `id`, `content`, and `chunkType` are optional so the type works
/// for both factual approved memories (tags: ["session-memory"]) and ephemeral
/// episodic summaries (sessionID + projectPath set).
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
/// `score` is a cosine similarity value in [0, 1] — higher is more relevant.
struct MemorySearchResult: Sendable {
    let chunk: MemoryChunk
    /// Cosine similarity score in [0, 1].
    let score: Float

    /// Converts this result into a `RAGChunk` for use in the existing RAG enrichment pipeline.
    /// The source field is set to "memory" so the UI can distinguish memory chunks from book chunks.
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
/// Conforming types are actors so all storage operations are automatically serialised.
/// `pluginID` and `displayName` are `nonisolated` so they can be read by the registry
/// without an `await`.
///
/// Built-in plugins:
///   - `NullMemoryPlugin` ("null") — no-op default, used when memory storage is disabled.
///   - `LocalVectorPlugin` ("local-vector") — SQLite + NLContextualEmbedding; added in phase 135b.
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

/// No-op memory backend. All writes are discarded; all searches return empty.
/// Used as the default when no backend is configured, and as the base for tests
/// that don't care about storage behaviour.
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
/// Ownership: `AppState` creates one registry at init, registers built-in plugins,
/// and sets the active plugin from `AppSettings.memoryBackendID`.
/// `AppState` then injects `registry.activePlugin` into `MemoryEngine` and `AgenticEngine`.
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

    /// Add a plugin to the registry. Does not change the active plugin.
    func register(_ plugin: any MemoryBackendPlugin) async {
        plugins[plugin.pluginID] = plugin
    }

    /// Set the active plugin by ID. If `pluginID` is not registered, the call is ignored.
    func setActive(pluginID: String) {
        guard plugins[pluginID] != nil else { return }
        activePluginID = pluginID
    }

    /// The currently active plugin. Falls back to `NullMemoryPlugin` if the stored ID
    /// is not in the registry (e.g. after a plugin is unregistered).
    var activePlugin: any MemoryBackendPlugin {
        plugins[activePluginID] ?? NullMemoryPlugin()
    }
}
