# Phase 25b — RAG Integration Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 25a complete: XcalibreClientTests.swift and RAGToolsTests.swift written (failing).

xcalibre-server facts:
  Base URL:      http://localhost:8083 (default; override via XCALIBRE_BASE_URL env var)
  Chunks:        GET /api/v1/search/chunks?q=<q>&limit=N&rerank=bool&book_ids[]=<id>
  Books:         GET /api/v1/books?page=1&page_size=200
  Health:        GET /health  (no auth, used for availability probe)
  Auth header:   Authorization: Bearer <token>
  Keychain:      service=com.merlin.xcalibre  account=api-token

Option C integration:
  - Auto-inject: 3 chunks prepended to every user message (rerank=false, fast)
  - Explicit tool: rag_search (up to 20 chunks, rerank optional)
  - Explicit tool: rag_list_books
  - All paths degrade silently when server is unavailable

---

## Write to: Merlin/RAG/XcalibreClient.swift

```swift
import Foundation
import Security

// MARK: - Models

struct RAGChunk: Codable, Sendable {
    var chunkID: String
    /// "books" or "memory" — distinguishes book content from Merlin memory chunks.
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
}

struct RAGAuthorRef: Codable, Sendable {
    var name: String
}

struct RAGBook: Codable, Sendable {
    var id: String
    var title: String
    var authors: [RAGAuthorRef]

    // Partial decoding: xcalibre Book has many fields; decode only what Merlin needs.
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

private struct BooksListResponse: Decodable {
    var items: [RAGBook]
}

// MARK: - XcalibreClient

actor XcalibreClient {
    static let keychainService = "com.merlin.xcalibre"
    static let keychainAccount = "api-token"

    private let baseURL: String
    private let fetcher: any HTTPFetching
    private(set) var isAvailable: Bool = false

    init(
        baseURL: String = ProcessInfo.processInfo.environment["XCALIBRE_BASE_URL"]
            ?? "http://localhost:8083",
        fetcher: any HTTPFetching = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.fetcher = fetcher
    }

    // MARK: - Keychain

    static func readAPIToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func writeAPIToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    // MARK: - Availability probe

    /// Fire-and-forget on app launch. Sets isAvailable based on /health response.
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

    /// Returns top matching chunks. Returns [] on any failure — never throws.
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
        guard isAvailable else { return [] }
        guard let token = XcalibreClient.readAPIToken(), !token.isEmpty else { return [] }

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
                return []
            }
            return (try? JSONDecoder().decode(ChunkSearchResponse.self, from: data))?.chunks ?? []
        } catch {
            isAvailable = false
            return []
        }
    }

    // MARK: - List books

    /// Returns all library books. Returns [] on any failure — never throws.
    func listBooks(limit: Int = 200) async -> [RAGBook] {
        guard isAvailable else { return [] }
        guard let token = XcalibreClient.readAPIToken(), !token.isEmpty else { return [] }

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
```

---

## Write to: Merlin/RAG/RAGTools.swift

```swift
import Foundation

enum RAGTools {

    // MARK: - Auto-inject (Option C)

    /// Builds the enriched user message for auto-injection.
    /// Returns the original message unchanged if chunks is empty.
    static func buildEnrichedMessage(_ userMessage: String, chunks: [RAGChunk]) -> String {
        guard !chunks.isEmpty else { return userMessage }
        return formatContextInjection(chunks) + "\n\n---\n\n" + userMessage
    }

    // MARK: - Tool handlers

    static func search(args: String, client: XcalibreClient) async -> String {
        struct Args: Decodable {
            var query: String
            var book_ids: [String]?
            var limit: Int?
            var rerank: Bool?
        }
        guard let decoded = try? JSONDecoder().decode(Args.self, from: Data(args.utf8)) else {
            return "Invalid arguments for rag_search."
        }
        guard await client.isAvailable else {
            return unavailableMessage
        }
        let chunks = await client.searchChunks(
            query: decoded.query,
            bookIDs: decoded.book_ids,
            limit: min(decoded.limit ?? 10, 20),
            rerank: decoded.rerank ?? false
        )
        guard !chunks.isEmpty else {
            return "No relevant passages found for: \(decoded.query)"
        }
        return formatChunks(chunks)
    }

    static func listBooks(client: XcalibreClient) async -> String {
        guard await client.isAvailable else {
            return unavailableMessage
        }
        let books = await client.listBooks()
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
```

---

## Modify: Merlin/Tools/ToolDefinitions.swift

Add to `all` array (append after `visionQuery`):

```swift
ragSearch, ragListBooks,
```

Add these two static properties anywhere in the file (e.g. after the vision tools):

```swift
// RAG
static let ragSearch = ToolDefinition(function: .init(
    name: "rag_search",
    description: "Search your personal library for relevant passages using semantic and keyword search. Use when you need to look something up in your books. Returns ranked text chunks with source and heading.",
    parameters: JSONSchema(
        type: "object",
        properties: [
            "query": JSONSchema(type: "string",
                description: "The search query"),
            "book_ids": JSONSchema(type: "array",
                description: "Optional book IDs to scope the search. Omit to search all books.",
                items: JSONSchema(type: "string", description: "Book ID")),
            "limit": JSONSchema(type: "integer",
                description: "Number of passages to return (1-20). Default: 10."),
            "rerank": JSONSchema(type: "boolean",
                description: "LLM reranking for higher quality at the cost of latency (~8s). Default: false."),
        ],
        required: ["query"]
    )
))

static let ragListBooks = ToolDefinition(function: .init(
    name: "rag_list_books",
    description: "List all books in your personal library with their IDs. Use before rag_search when you want to scope results to a specific book.",
    parameters: JSONSchema(
        type: "object",
        properties: [:],
        required: []
    )
))
```

---

## Modify: Merlin/Engine/AgenticEngine.swift

**Add property** after `weak var sessionStore: SessionStore?`:

```swift
var xcalibreClient: XcalibreClient?
```

**Add parameter** to `init`:

```swift
init(proProvider: any LLMProvider,
     flashProvider: any LLMProvider,
     visionProvider: LMStudioProvider,
     toolRouter: ToolRouter,
     contextManager: ContextManager,
     xcalibreClient: XcalibreClient? = nil) {
    self.proProvider = proProvider
    self.flashProvider = flashProvider
    self.visionProvider = visionProvider
    self.toolRouter = toolRouter
    self.contextManager = contextManager
    self.xcalibreClient = xcalibreClient
}
```

**Modify `runLoop`** — replace the first line:

```swift
// Before:
contextManager.append(Message(role: .user, content: .text(userMessage), timestamp: Date()))

// After:
var effectiveMessage = userMessage
if let client = xcalibreClient {
    let chunks = await client.searchChunks(query: userMessage, limit: 3, rerank: false)
    if !chunks.isEmpty {
        effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: chunks)
        continuation.yield(.systemNote("Library: \(chunks.count) passage\(chunks.count == 1 ? "" : "s") retrieved"))
    }
}
contextManager.append(Message(role: .user, content: .text(effectiveMessage), timestamp: Date()))
```

---

## Modify: Merlin/App/AppState.swift

**Add property** (after `let ctx = ContextManager()`):

```swift
let xcalibreClient = XcalibreClient()
```

**Pass to engine** — replace the `engine = AgenticEngine(...)` call:

```swift
engine = AgenticEngine(
    proProvider: pro,
    flashProvider: flash,
    visionProvider: vision,
    toolRouter: toolRouter,
    contextManager: ctx,
    xcalibreClient: xcalibreClient
)
```

**Probe in background** — add after `engine.sessionStore = sessionStore`:

```swift
Task { await xcalibreClient.probe() }
```

**Register RAG tools** — add inside `init()`, after the existing `run_shell` registration block:

```swift
toolRouter.register(name: "rag_search") { [weak self] args in
    guard let client = self?.engine?.xcalibreClient else {
        return "RAG service not configured."
    }
    return await RAGTools.search(args: args, client: client)
}

toolRouter.register(name: "rag_list_books") { [weak self] _ in
    guard let client = self?.engine?.xcalibreClient else {
        return "RAG service not configured."
    }
    return await RAGTools.listBooks(client: client)
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'warning:|error:|BUILD'
```

Expected: `TEST BUILD SUCCEEDED` with zero errors and zero warnings.

Then run the unit tests:

```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' \
    -only-testing:MerlinTests/XcalibreClientTests \
    -only-testing:MerlinTests/RAGToolsTests \
    2>&1 | grep -E 'passed|failed|error:'
```

Expected: `XcalibreClientTests` — 8 tests passed. `RAGToolsTests` — 5 tests passed.

To set the API token manually for live testing:

```bash
security add-generic-password -s com.merlin.xcalibre -a api-token -w <your-token>
```

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/RAG/XcalibreClient.swift \
        Merlin/RAG/RAGTools.swift \
        Merlin/Tools/ToolDefinitions.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/App/AppState.swift
git commit -m "Phase 25b — RAG integration: XcalibreClient + auto-inject + rag_search + rag_list_books"
```
