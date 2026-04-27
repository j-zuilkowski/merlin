import Foundation

// MARK: - Models

struct RAGChunk: Codable, Sendable {
    var chunkID: String
    var bookID: String
    var bookTitle: String
    var headingPath: String?
    var chunkType: String
    var text: String
    var wordCount: Int
    var rrfScore: Double
    var rerankScore: Double?

    enum CodingKeys: String, CodingKey {
        case chunkID = "chunk_id"
        case bookID = "book_id"
        case bookTitle = "book_title"
        case headingPath = "heading_path"
        case chunkType = "chunk_type"
        case text
        case wordCount = "word_count"
        case rrfScore = "rrf_score"
        case rerankScore = "rerank_score"
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

    // MARK: - Search chunks

    func searchChunks(
        query: String,
        bookIDs: [String]? = nil,
        limit: Int = 5,
        rerank: Bool = false
    ) async -> [RAGChunk] {
        guard isAvailable else { return [] }
        guard !token.isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/api/v1/search/chunks")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "rerank", value: rerank ? "true" : "false")
        ]
        bookIDs?.forEach { items.append(URLQueryItem(name: "book_ids[]", value: $0)) }
        components.queryItems = items

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await fetcher.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                isAvailable = false
                return []
            }
            return (try? JSONDecoder().decode(ChunkSearchResponse.self, from: data))?.chunks ?? []
        } catch {
            isAvailable = false
            return []
        }
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
