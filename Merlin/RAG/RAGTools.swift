import Foundation

enum RAGTools {

    // MARK: - Auto-inject

    static func buildEnrichedMessage(_ userMessage: String, chunks: [RAGChunk]) -> String {
        guard !chunks.isEmpty else { return userMessage }
        return formatContextInjection(chunks) + "\n\n---\n\n" + userMessage
    }

    // MARK: - Tool handlers

    static func search(
        args: String,
        client: any XcalibreClientProtocol,
        projectPath: String? = nil
    ) async -> String {
        struct Args: Decodable {
            var query: String
            var source: String?
            var bookIDs: [String]?
            var projectPath: String?
            var limit: Int?
            var rerank: Bool?

            enum CodingKeys: String, CodingKey {
                case query
                case source
                case bookIDs = "book_ids"
                case projectPath = "project_path"
                case limit
                case rerank
            }
        }

        guard let decoded = try? JSONDecoder().decode(Args.self, from: Data(args.utf8)) else {
            return "Invalid arguments for rag_search."
        }
        guard await client.isAvailable() else {
            return unavailableMessage
        }

        let effectiveProjectPath = decoded.projectPath?.isEmpty == false
            ? decoded.projectPath
            : projectPath

        let chunks = await client.searchChunks(
            query: decoded.query,
            source: decoded.source ?? "books",
            bookIDs: decoded.bookIDs,
            projectPath: effectiveProjectPath,
            limit: min(max(decoded.limit ?? 10, 1), 20),
            rerank: decoded.rerank ?? false
        )
        guard !chunks.isEmpty else {
            return "No relevant passages found for: \(decoded.query)"
        }
        return formatChunks(chunks)
    }

    static func listBooks(client: any XcalibreClientProtocol) async -> String {
        guard await client.isAvailable() else {
            return unavailableMessage
        }
        let books = await client.listBooks(limit: 200)
        guard !books.isEmpty else {
            return "No books found in the library."
        }
        return formatBooks(books)
    }

    // MARK: - Formatting

    static func formatChunks(_ chunks: [RAGChunk]) -> String {
        chunks.enumerated().map { i, chunk in
            let location = [chunk.bookTitle, chunk.headingPath]
                .compactMap { $0 }
                .joined(separator: " › ")
            return "[\(i + 1)] \(location)\n\(chunk.text)"
        }.joined(separator: "\n\n---\n\n")
    }

    static func formatBooks(_ books: [RAGBook]) -> String {
        books.enumerated().map { i, book in
            let authors = book.authors.map(\.name).joined(separator: ", ")
            let authorSuffix = authors.isEmpty ? "" : " — \(authors)"
            return "\(i + 1). [\(book.id)] \(book.title)\(authorSuffix)"
        }.joined(separator: "\n")
    }

    static func formatContextInjection(_ chunks: [RAGChunk]) -> String {
        let body = chunks.enumerated().map { i, chunk in
            let location = [chunk.bookTitle, chunk.headingPath]
                .compactMap { $0 }
                .joined(separator: " › ")
            return "**\(i + 1). \(location)**\n\(chunk.text)"
        }.joined(separator: "\n\n")
        return "[Relevant passages from your library]\n\n\(body)"
    }

    // MARK: - Helpers

    private static let unavailableMessage =
        "RAG service unavailable. Start xcalibre-server at localhost:8083 to enable library search."
}
