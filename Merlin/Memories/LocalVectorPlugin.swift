import Foundation
import SQLite3

// MARK: - LocalVectorPlugin

/// Memory backend plugin that stores chunks in SQLite and ranks them with cosine
/// similarity over on-device embeddings.
///
/// Production storage lives at `~/.merlin/memory.sqlite`. Approved factual memories and
/// episodic summaries both land here. `write(_:)` computes the embedding during the call
/// so the inserted row is immediately searchable. `search(query:topK:)` loads all rows
/// with a non-NULL embedding, computes cosine similarity in Swift, and returns the top-K
/// results. That brute-force scan is fast enough for hundreds to low thousands of chunks.
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

    // MARK: - MemoryBackendPlugin

    func write(_ chunk: MemoryChunk) async throws {
        try ensureOpen()
        // Compute the embedding before persisting so the row can be searched right away.
        let embedding = try? await embeddingProvider.embed(chunk.content)
        let tagsJSON = (try? JSONEncoder().encode(chunk.tags))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        try execute(
            sql: """
                INSERT OR REPLACE INTO memory_chunks
                    (id, content, chunk_type, tags, session_id, project_path, created_at, embedding)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
            bindings: [
                .text(chunk.id),
                .text(chunk.content),
                .text(chunk.chunkType),
                .text(tagsJSON),
                chunk.sessionID.map { .text($0) } ?? .null,
                chunk.projectPath.map { .text($0) } ?? .null,
                .real(chunk.createdAt.timeIntervalSince1970),
                embedding.map { .blob(Self.blob(from: $0)) } ?? .null
            ]
        )
    }

    func search(query: String, topK: Int) async throws -> [MemorySearchResult] {
        guard topK > 0 else { return [] }
        try ensureOpen()

        guard let queryVector = try? await embeddingProvider.embed(query) else {
            return []
        }

        let rows = try fetchAllEmbedded()
        let scored = rows.map { row -> MemorySearchResult in
            MemorySearchResult(chunk: row.chunk, score: cosine(queryVector, row.embedding))
        }
        .sorted { left, right in
            if left.score == right.score {
                return left.chunk.createdAt > right.chunk.createdAt
            }
            return left.score > right.score
        }

        return Array(scored.prefix(topK))
    }

    /// Remove the row with the matching memory chunk ID.
    func delete(id: String) async throws {
        try ensureOpen()
        try execute(
            sql: "DELETE FROM memory_chunks WHERE id = ?;",
            bindings: [.text(id)]
        )
    }

    // MARK: - SQLite

    private enum Binding {
        case text(String)
        case blob(Data)
        case real(Double)
        case null
    }

    private func ensureOpen() throws {
        guard db == nil else { return }

        var connection: OpaquePointer?
        guard sqlite3_open(databasePath, &connection) == SQLITE_OK, let connection else {
            if let connection {
                sqlite3_close(connection)
            }
            throw LocalVectorError.cannotOpenDatabase(databasePath)
        }

        db = connection
        do {
            // Actual schema used by the plugin; the embedding column is nullable until the
            // row has been written with vector data.
            try execute(
                sql: """
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
                    """,
                bindings: []
            )
        } catch {
            sqlite3_close(connection)
            db = nil
            throw error
        }
    }

    private func execute(sql: String, bindings: [Binding]) throws {
        guard let db else {
            throw LocalVectorError.cannotOpenDatabase(databasePath)
        }

        let statements = sql
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for statement in statements {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, statement, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                throw LocalVectorError.cannotOpenDatabase(databasePath)
            }
            defer { sqlite3_finalize(stmt) }

            for (index, binding) in bindings.enumerated() {
                let column = Int32(index + 1)
                switch binding {
                case .text(let value):
                    value.withCString { cString in
                        _ = sqlite3_bind_text(stmt, column, cString, -1, Self.sqliteTransient)
                    }
                case .blob(let data):
                    _ = data.withUnsafeBytes { rawBuffer in
                        sqlite3_bind_blob(stmt, column, rawBuffer.baseAddress, Int32(rawBuffer.count), Self.sqliteTransient)
                    }
                case .real(let value):
                    _ = sqlite3_bind_double(stmt, column, value)
                case .null:
                    _ = sqlite3_bind_null(stmt, column)
                }
            }

            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else {
                throw LocalVectorError.cannotOpenDatabase(databasePath)
            }
        }
    }

    private struct EmbeddedRow {
        let chunk: MemoryChunk
        let embedding: [Float]
    }

    private func fetchAllEmbedded() throws -> [EmbeddedRow] {
        guard let db else {
            return []
        }

        let sql = """
            SELECT id, content, chunk_type, tags, session_id, project_path, created_at, embedding
            FROM memory_chunks
            WHERE embedding IS NOT NULL;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw LocalVectorError.cannotOpenDatabase(databasePath)
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [EmbeddedRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let id = columnString(stmt, 0),
                let content = columnString(stmt, 1),
                let chunkType = columnString(stmt, 2),
                let tagsJSON = columnString(stmt, 3)
            else {
                continue
            }

            let sessionID = columnString(stmt, 4)
            let projectPath = columnString(stmt, 5)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
            guard let embeddingData = columnData(stmt, 7) else {
                continue
            }

            let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
            // Rows without embeddings are skipped by the SELECT clause, but keep this guard
            // so corrupted rows do not crash the search path.
            let embedding = Self.floats(from: embeddingData)

            rows.append(
                EmbeddedRow(
                    chunk: MemoryChunk(
                        id: id,
                        content: content,
                        chunkType: chunkType,
                        tags: tags,
                        sessionID: sessionID,
                        projectPath: projectPath,
                        createdAt: createdAt
                    ),
                    embedding: embedding
                )
            )
        }

        return rows
    }

    private func columnString(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self))
    }

    private func columnData(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard let blob = sqlite3_column_blob(stmt, index) else {
            return nil
        }
        let length = Int(sqlite3_column_bytes(stmt, index))
        guard length > 0 else {
            return Data()
        }
        return Data(bytes: blob, count: length)
    }

    // MARK: - Similarity

    /// Cosine similarity between two Float vectors.
    ///
    /// Returns 0 when the vectors differ in length or either one has zero magnitude.
    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in 0..<a.count {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }

        let denominator = normA.squareRoot() * normB.squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }

    // MARK: - Vector Encoding

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func blob(from vector: [Float]) -> Data {
        guard !vector.isEmpty else {
            return Data()
        }
        let copy = vector
        return copy.withUnsafeBytes { rawBuffer in
            Data(bytes: rawBuffer.baseAddress!, count: rawBuffer.count)
        }
    }

    private static func floats(from data: Data) -> [Float] {
        guard !data.isEmpty else {
            return []
        }

        let count = data.count / MemoryLayout<Float>.size
        var values = [Float](repeating: 0, count: count)
        values.withUnsafeMutableBytes { destination in
            _ = data.copyBytes(to: destination)
        }
        return values
    }
}

// MARK: - LocalVectorError

enum LocalVectorError: Error, Sendable {
    /// The SQLite database at `databasePath` could not be opened.
    case cannotOpenDatabase(String)
}
