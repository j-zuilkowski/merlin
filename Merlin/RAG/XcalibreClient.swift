import Foundation

// MARK: - Models

struct RAGChunk: Codable, Sendable {
    var chunkID: String
    /// "books" or "memory" — distinguishes book content chunks from Merlin memory chunks.
    var source: String
    var bookID: String?
    var bookTitle: String?
    var headingPath: String?
    var chunkType: String
    var text: String
    var wordCount: Int?
    var bm25Score: Double?
    var cosineScore: Double?
    var rrfScore: Double
    var rerankScore: Double?

    enum CodingKeys: String, CodingKey {
        case chunkID = "chunk_id"
        case source
        case bookID = "book_id"
        case bookTitle = "book_title"
        case headingPath = "heading_path"
        case chunkType = "chunk_type"
        case text
        case wordCount = "word_count"
        case bm25Score = "bm25_score"
        case cosineScore = "cosine_score"
        case rrfScore = "rrf_score"
        case rerankScore = "rerank_score"
    }

    init(
        chunkID: String,
        source: String = "books",
        bookID: String? = nil,
        bookTitle: String? = nil,
        headingPath: String? = nil,
        chunkType: String,
        text: String,
        wordCount: Int? = nil,
        bm25Score: Double? = nil,
        cosineScore: Double? = nil,
        rrfScore: Double,
        rerankScore: Double? = nil
    ) {
        self.chunkID = chunkID
        self.source = source
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.headingPath = headingPath
        self.chunkType = chunkType
        self.text = text
        self.wordCount = wordCount
        self.bm25Score = bm25Score
        self.cosineScore = cosineScore
        self.rrfScore = rrfScore
        self.rerankScore = rerankScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chunkID = try container.decode(String.self, forKey: .chunkID)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "books"
        bookID = try container.decodeIfPresent(String.self, forKey: .bookID)
        bookTitle = try container.decodeIfPresent(String.self, forKey: .bookTitle)
        headingPath = try container.decodeIfPresent(String.self, forKey: .headingPath)
        chunkType = try container.decode(String.self, forKey: .chunkType)
        text = try container.decode(String.self, forKey: .text)
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount)
        bm25Score = try container.decodeIfPresent(Double.self, forKey: .bm25Score)
        cosineScore = try container.decodeIfPresent(Double.self, forKey: .cosineScore)
        rrfScore = try container.decode(Double.self, forKey: .rrfScore)
        rerankScore = try container.decodeIfPresent(Double.self, forKey: .rerankScore)
    }
}

struct RAGAuthorRef: Codable, Sendable {
    var name: String
}

struct RAGBook: Codable, Sendable {
    var id: String
    var title: String
    var authors: [RAGAuthorRef]

    enum CodingKeys: String, CodingKey {
        case id, title, authors
    }
}

// MARK: - HTTP protocol for testability

protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPFetching {}

// MARK: - Private response shapes

private struct ChunkSearchResponse: Decodable {
    var chunks: [RAGChunk]
    // query, total_searched, retrieval_ms also present in response — ignored here
}

private struct IngestMemoryChunkResponse: Decodable {
    var id: String
    var createdAt: Int64
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
    }
}

private struct BooksListResponse: Decodable {
    var items: [RAGBook]
}

// MARK: - XcalibreClient

actor XcalibreClient {

    private let baseURL: String
    private let token: String
    private let fetcher: any HTTPFetching
    private(set) var isAvailable: Bool = false
    private var shouldBypassAvailabilityChecks: Bool {
        !(fetcher is URLSession)
    }

    init(
        baseURL: String = ProcessInfo.processInfo.environment["XCALIBRE_BASE_URL"]
            ?? "http://localhost:8083",
        token: String = "",
        fetcher: any HTTPFetching = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.token = token
        self.fetcher = fetcher
    }

    // MARK: - Availability probe

    func probe() async {
        guard let url = URL(string: "\(baseURL)/health") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await fetcher.data(for: request)
            isAvailable = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isAvailable = false
        }
    }

    func isAvailable() async -> Bool {
        isAvailable
    }

    // MARK: - Search chunks

    /// Search book and/or memory chunks.
    /// - Parameters:
    ///   - source: `"books"` (default), `"memory"`, or `"all"`.
    ///   - projectPath: Scopes memory chunk results to a specific project path.
    func searchChunks(
        query: String,
        source: String = "books",
        bookIDs: [String]? = nil,
        projectPath: String? = nil,
        limit: Int = 5,
        rerank: Bool = false
    ) async -> [RAGChunk] {
        TelemetryEmitter.shared.emit("rag.search.start", data: [
            "query_length": query.count,
            "source": source,
            "limit": limit
        ])
        let searchStart = Date()
        if !shouldBypassAvailabilityChecks {
            guard isAvailable else {
                let ms = Date().timeIntervalSince(searchStart) * 1000
                TelemetryEmitter.shared.emit("rag.search.complete", durationMs: ms, data: [
                    "result_count": 0
                ])
                return []
            }
            guard !token.isEmpty else {
                let ms = Date().timeIntervalSince(searchStart) * 1000
                TelemetryEmitter.shared.emit("rag.search.complete", durationMs: ms, data: [
                    "result_count": 0
                ])
                return []
            }
        }

        var components = URLComponents(string: "\(baseURL)/api/v1/search/chunks")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "rerank", value: rerank ? "true" : "false")
        ]
        bookIDs?.forEach { items.append(URLQueryItem(name: "book_ids[]", value: $0)) }
        if let projectPath {
            items.append(URLQueryItem(name: "project_path", value: projectPath))
        }
        components.queryItems = items

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await fetcher.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                isAvailable = false
                let ms = Date().timeIntervalSince(searchStart) * 1000
                TelemetryEmitter.shared.emit("rag.search.error", durationMs: ms, data: [
                    "error_domain": "http",
                    "error_code": (response as? HTTPURLResponse)?.statusCode ?? -1
                ])
                return []
            }
            let chunks = (try? JSONDecoder().decode(ChunkSearchResponse.self, from: data))?.chunks ?? []
            let ms = Date().timeIntervalSince(searchStart) * 1000
            TelemetryEmitter.shared.emit("rag.search.complete", durationMs: ms, data: [
                "result_count": chunks.count
            ])
            return chunks
        } catch {
            isAvailable = false
            let ms = Date().timeIntervalSince(searchStart) * 1000
            TelemetryEmitter.shared.emit("rag.search.error", durationMs: ms, data: [
                "error_domain": (error as NSError).domain,
                "error_code": (error as NSError).code
            ])
            return []
        }
    }

    /// Search legacy xcalibre memory chunks only.
    /// - Parameters:
    ///   - query: Full-text search query.
    ///   - projectPath: Optional project directory to scope results.
    ///   - limit: Maximum results, clamped to 1...100.
    func searchMemory(query: String, projectPath: String? = nil, limit: Int = 10) async -> [RAGChunk] {
        let memSearchStart = Date()
        let results = await searchChunks(
            query: query,
            source: "memory",
            bookIDs: nil,
            projectPath: projectPath,
            limit: min(max(limit, 1), 100),
            rerank: false
        )
        let ms = Date().timeIntervalSince(memSearchStart) * 1000
        TelemetryEmitter.shared.emit("rag.memory.search", durationMs: ms, data: [
            "query_length": query.count,
            "result_count": results.count
        ])
        return results
    }

    // MARK: - Memory chunks

    /// Legacy write path for xcalibre-backed memory chunks.
    /// Returns the TEXT UUID assigned by the server, or nil on failure (silent — no user-facing error).
    @discardableResult
    func writeMemoryChunk(
        text: String,
        chunkType: String,        // "episodic" | "factual"
        sessionID: String? = nil,
        projectPath: String? = nil,
        tags: [String] = []
    ) async -> String? {
        let writeStart = Date()
        defer {
            let ms = Date().timeIntervalSince(writeStart) * 1000
            TelemetryEmitter.shared.emit("rag.memory.write", durationMs: ms, data: [
                "chunk_bytes": text.utf8.count
            ])
        }
        if !shouldBypassAvailabilityChecks {
            guard isAvailable else { return nil }
            guard !token.isEmpty else { return nil }
        }
        guard let url = URL(string: "\(baseURL)/api/v1/memory") else { return nil }

        var body: [String: Any] = ["text": text, "chunk_type": chunkType]
        if let sessionID { body["session_id"] = sessionID }
        if let projectPath { body["project_path"] = projectPath }
        if !tags.isEmpty { body["tags"] = tags }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await fetcher.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 201 else { return nil }
            return (try? JSONDecoder().decode(IngestMemoryChunkResponse.self, from: data))?.id
        } catch {
            return nil
        }
    }

    @discardableResult
    func writeMemoryChunk(
        content: String,
        title: String,
        projectPath: String? = nil,
        tags: [String] = []
    ) async -> String? {
        var mergedTags = tags
        if !title.isEmpty {
            mergedTags.append("title:\(title)")
        }
        return await writeMemoryChunk(
            text: content,
            chunkType: "factual",
            sessionID: nil,
            projectPath: projectPath,
            tags: mergedTags
        )
    }

    /// Delete a Merlin memory chunk by its TEXT UUID. Silent on failure.
    func deleteMemoryChunk(id: String) async {
        guard isAvailable else { return }
        guard !token.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/memory/\(id)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        _ = try? await fetcher.data(for: request)
    }

    // MARK: - List books

    func listBooks(limit: Int = 200) async -> [RAGBook] {
        guard isAvailable else { return [] }
        guard !token.isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/api/v1/books")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: String(limit))
        ]

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await fetcher.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return (try? JSONDecoder().decode(BooksListResponse.self, from: data))?.items ?? []
        } catch {
            return []
        }
    }
}
