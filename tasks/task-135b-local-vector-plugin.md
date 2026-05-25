# Phase 135b — LocalVectorPlugin Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 135a complete: failing tests for LocalVectorPlugin and EmbeddingProviderProtocol in place.

---

## Write to: Merlin/Memories/EmbeddingProvider.swift

```swift
import Foundation
import NaturalLanguage

// MARK: - EmbeddingProviderProtocol

/// Produces a fixed-length floating-point embedding vector for a text string.
/// Conforming types must be `Sendable` (struct or actor).
///
/// The `dimension` property declares the output size of every vector returned by `embed(_:)`.
/// Callers may use this to pre-allocate accumulator buffers.
protocol EmbeddingProviderProtocol: Sendable {
    /// Number of dimensions in the embedding vector returned by `embed(_:)`.
    var dimension: Int { get }
    /// Produce a normalised embedding for `text`. Throws if the underlying model is
    /// unavailable or `text` is empty.
    func embed(_ text: String) async throws -> [Float]
}

// MARK: - EmbeddingError

enum EmbeddingError: Error, Sendable {
    /// The NLContextualEmbedding model assets are not available on this device.
    case modelUnavailable
    /// The input text produced no tokens (e.g. empty or whitespace-only string).
    case emptyInput
}

// MARK: - NLContextualEmbeddingProvider

/// Production embedding provider backed by `NLContextualEmbedding` (macOS 14+).
///
/// On first call, `requestAssets` downloads the Apple neural embedding model (~50 MB) and
/// caches it in the system asset store. Subsequent calls are instant.
///
/// The sentence embedding is computed by mean-pooling the per-token contextual vectors
/// returned by `NLContextualEmbedding.write(string:language:unit:usingBlock:)`.
/// This produces a 512-dimensional Float vector for the standard English model.
struct NLContextualEmbeddingProvider: EmbeddingProviderProtocol {
    /// 512 dimensions for the standard Apple English contextual embedding model.
    let dimension: Int = 512

    func embed(_ text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }

        let model = NLContextualEmbedding(language: .english)

        // Request model assets. If already downloaded this returns immediately.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            model.requestAssets { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if result == .notAvailable {
                    continuation.resume(throwing: EmbeddingError.modelUnavailable)
                } else {
                    continuation.resume()
                }
            }
        }

        // Collect per-token embeddings; mean-pool to produce a sentence vector.
        var accumulator = [Double](repeating: 0.0, count: dimension)
        var tokenCount = 0

        try model.write(string: text, language: .english, unit: .word) { tokenVector, _, _ in
            let count = min(tokenVector.count, self.dimension)
            for i in 0..<count {
                accumulator[i] += tokenVector[i]
            }
            tokenCount += 1
        }

        guard tokenCount > 0 else {
            throw EmbeddingError.emptyInput
        }

        let scale = 1.0 / Double(tokenCount)
        return accumulator.map { Float($0 * scale) }
    }
}
```

---

## Write to: Merlin/Memories/LocalVectorPlugin.swift

```swift
import Foundation
import SQLite3

// MARK: - LocalVectorPlugin

/// Memory backend plugin that stores chunks in a local SQLite database and retrieves
/// them using cosine similarity over `NLContextualEmbedding` embeddings.
///
/// Storage path: `~/.merlin/memory.sqlite` in production; injected in tests.
///
/// Schema (created on first use):
/// ```sql
/// CREATE TABLE memory_chunks (
///     id TEXT PRIMARY KEY,
///     content TEXT NOT NULL,
///     chunk_type TEXT NOT NULL,
///     tags TEXT NOT NULL,        -- JSON array of strings
///     session_id TEXT,
///     project_path TEXT,
///     created_at REAL NOT NULL,
///     embedding BLOB             -- NULL until async embedding completes; skipped in search
/// );
/// ```
///
/// Retrieval strategy: load all rows that have a non-NULL embedding, compute cosine
/// similarity between the query embedding and each stored embedding in Swift, sort
/// descending, return the top-K results.  At memory scale (hundreds to low thousands
/// of chunks) this is fast enough without an approximate-search index.
actor LocalVectorPlugin: MemoryBackendPlugin {
    nonisolated let pluginID = "local-vector"
    nonisolated let displayName = "Local (on-device)"

    private let databasePath: String
    private let embeddingProvider: any EmbeddingProviderProtocol
    private var db: OpaquePointer?

    init(databasePath: String, embeddingProvider: any EmbeddingProviderProtocol) {
        self.databasePath = databasePath
        self.embeddingProvider = embeddingProvider
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - MemoryBackendPlugin

    func write(_ chunk: MemoryChunk) async throws {
        try ensureOpen()
        let tagsJSON = (try? JSONEncoder().encode(chunk.tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        // Insert the row immediately (embedding = NULL); update embedding asynchronously.
        let insertSQL = """
            INSERT OR REPLACE INTO memory_chunks
                (id, content, chunk_type, tags, session_id, project_path, created_at, embedding)
            VALUES (?, ?, ?, ?, ?, ?, ?, NULL);
            """
        try execute(sql: insertSQL, bindings: [
            .text(chunk.id),
            .text(chunk.content),
            .text(chunk.chunkType),
            .text(tagsJSON),
            chunk.sessionID.map { .text($0) } ?? .null,
            chunk.projectPath.map { .text($0) } ?? .null,
            .real(chunk.createdAt.timeIntervalSince1970)
        ])

        // Embed and update in the background — write() returns immediately.
        let content = chunk.content
        let chunkID = chunk.id
        Task { [weak self] in
            guard let self else { return }
            if let vector = try? await embeddingProvider.embed(content) {
                await self.updateEmbedding(id: chunkID, vector: vector)
            }
        }
    }

    func search(query: String, topK: Int) async throws -> [MemorySearchResult] {
        try ensureOpen()
        guard let queryVector = try? await embeddingProvider.embed(query) else { return [] }

        let rows = try fetchAllEmbedded()
        var scored: [(chunk: MemoryChunk, score: Float)] = []
        for row in rows {
            let sim = cosine(queryVector, row.embedding)
            scored.append((row.chunk, sim))
        }
        scored.sort { $0.score > $1.score }
        return scored.prefix(topK).map { MemorySearchResult(chunk: $0.chunk, score: $0.score) }
    }

    func delete(id: String) async throws {
        try ensureOpen()
        try execute(sql: "DELETE FROM memory_chunks WHERE id = ?;", bindings: [.text(id)])
    }

    // MARK: - Private: embedding update

    private func updateEmbedding(id: String, vector: [Float]) {
        guard let db else { return }
        let blob = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        let sql = "UPDATE memory_chunks SET embedding = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        blob.withUnsafeBytes { ptr in
            _ = sqlite3_bind_blob(stmt, 1, ptr.baseAddress, Int32(blob.count), nil)
        }
        _ = sqlite3_bind_text(stmt, 2, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        _ = sqlite3_step(stmt)
    }

    // MARK: - Private: fetch rows with embeddings

    private struct EmbeddedRow {
        let chunk: MemoryChunk
        let embedding: [Float]
    }

    private func fetchAllEmbedded() throws -> [EmbeddedRow] {
        guard let db else { return [] }
        let sql = """
            SELECT id, content, chunk_type, tags, session_id, project_path, created_at, embedding
            FROM memory_chunks
            WHERE embedding IS NOT NULL;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [EmbeddedRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id       = String(cString: sqlite3_column_text(stmt, 0))
            let content  = String(cString: sqlite3_column_text(stmt, 1))
            let type_    = String(cString: sqlite3_column_text(stmt, 2))
            let tagsStr  = String(cString: sqlite3_column_text(stmt, 3))
            let sessRaw  = sqlite3_column_text(stmt, 4)
            let projRaw  = sqlite3_column_text(stmt, 5)
            let created  = sqlite3_column_double(stmt, 6)
            let blobPtr  = sqlite3_column_blob(stmt, 7)
            let blobLen  = sqlite3_column_bytes(stmt, 7)

            let tags = (try? JSONDecoder().decode([String].self, from: Data((tagsStr).utf8))) ?? []
            let sessionID   = sessRaw.map { String(cString: $0) }
            let projectPath = projRaw.map { String(cString: $0) }

            guard let blobPtr, blobLen > 0 else { continue }
            let floatCount = Int(blobLen) / MemoryLayout<Float>.size
            let embedding = Array(UnsafeBufferPointer(
                start: blobPtr.assumingMemoryBound(to: Float.self),
                count: floatCount
            ))

            let chunk = MemoryChunk(
                id: id, content: content, chunkType: type_,
                tags: tags, sessionID: sessionID, projectPath: projectPath,
                createdAt: Date(timeIntervalSince1970: created)
            )
            rows.append(EmbeddedRow(chunk: chunk, embedding: embedding))
        }
        return rows
    }

    // MARK: - Private: SQLite helpers

    private enum Binding {
        case text(String)
        case real(Double)
        case null
    }

    private func ensureOpen() throws {
        guard db == nil else { return }
        guard sqlite3_open(databasePath, &db) == SQLITE_OK else {
            throw LocalVectorError.cannotOpenDatabase(databasePath)
        }
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS memory_chunks (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                chunk_type TEXT NOT NULL,
                tags TEXT NOT NULL DEFAULT '[]',
                session_id TEXT,
                project_path TEXT,
                created_at REAL NOT NULL,
                embedding BLOB
            );
            CREATE INDEX IF NOT EXISTS idx_mc_created ON memory_chunks(created_at DESC);
            """, bindings: [])
    }

    private func execute(sql: String, bindings: [Binding]) throws {
        guard let db else { return }
        // Split on semicolons to support multi-statement strings (schema creation).
        let statements = sql.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for stmt_sql in statements {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, stmt_sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            for (i, binding) in bindings.enumerated() {
                let col = Int32(i + 1)
                switch binding {
                case .text(let s):
                    _ = sqlite3_bind_text(stmt, col, s, -1,
                                         unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                case .real(let d):
                    _ = sqlite3_bind_double(stmt, col, d)
                case .null:
                    _ = sqlite3_bind_null(stmt, col)
                }
            }
            _ = sqlite3_step(stmt)
        }
    }

    // MARK: - Private: cosine similarity

    /// Cosine similarity between two equal-length Float vectors.
    /// Returns 0 if either vector is zero-magnitude or lengths differ.
    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot   += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = normA.squareRoot() * normB.squareRoot()
        return denom > 0 ? dot / denom : 0
    }
}

// MARK: - LocalVectorError

enum LocalVectorError: Error, Sendable {
    case cannotOpenDatabase(String)
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
Expected: BUILD SUCCEEDED — all 135a tests pass, zero warnings.

## Commit
```bash
git add Merlin/Memories/EmbeddingProvider.swift
git add Merlin/Memories/LocalVectorPlugin.swift
git commit -m "Phase 135b — LocalVectorPlugin: SQLite + NLContextualEmbedding cosine search"
```
