# Phase 111b — rag_search Tool Source/ProjectPath Parameters

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 111a complete: RAGSearchToolTests (failing) in place.

---

## Edit: Merlin/RAG/RAGTools.swift — add source + projectPath to search handler

```swift
// BEFORE:
static func search(args: String, client: any XcalibreClientProtocol) async -> String {
    struct Args: Decodable {
        var query: String
        var bookIDs: [String]?
        var limit: Int?
        var rerank: Bool?
    }

    guard let decoded = try? JSONDecoder().decode(Args.self, from: Data(args.utf8)) else {
        return "Invalid arguments for rag_search."
    }
    guard await client.isAvailable() else {
        return unavailableMessage
    }

    let chunks = await client.searchChunks(
        query: decoded.query,
        source: "books",
        bookIDs: decoded.bookIDs,
        projectPath: nil,
        limit: min(max(decoded.limit ?? 10, 1), 20),
        rerank: decoded.rerank ?? false
    )
    guard !chunks.isEmpty else {
        return "No relevant passages found for: \(decoded.query)"
    }
    return formatChunks(chunks)
}

// AFTER:
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
        // project_path can be provided by the agent as an alternative key
        enum CodingKeys: String, CodingKey {
            case query, source, bookIDs = "book_ids", projectPath = "project_path", limit, rerank
        }
    }

    guard let decoded = try? JSONDecoder().decode(Args.self, from: Data(args.utf8)) else {
        return "Invalid arguments for rag_search."
    }
    guard await client.isAvailable() else {
        return unavailableMessage
    }

    // project_path precedence: args > handler parameter
    let effectiveProjectPath = decoded.projectPath ?? projectPath

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
```

---

## Edit: Merlin/Tools/ToolDefinitions.swift — update ragSearch schema

```swift
// BEFORE:
static let ragSearch = ToolDefinition(function: .init(
    name: "rag_search",
    // ... existing description and parameters ...
))

// AFTER — update the parameters object to add source and project_path:
static let ragSearch = ToolDefinition(function: .init(
    name: "rag_search",
    description: """
    Search your personal library and memory for relevant passages using semantic + keyword search.
    Returns numbered excerpts with source locations.
    Use source="memory" to search only session memory, "books" for books only (default), "all" for both.
    """,
    parameters: .object(
        properties: [
            "query": .string(description: "The search query."),
            "source": .string(
                description: #"Scope of search: "books" (default), "memory", or "all"."#,
                enum: ["books", "memory", "all"]
            ),
            "book_ids": .array(
                items: .string(description: "Book ID"),
                description: "Optional list of book IDs to restrict results. Only applies when source includes books."
            ),
            "project_path": .string(
                description: "Optional project directory to scope memory results. Overrides the engine default."
            ),
            "limit": .integer(description: "Number of results (1–20, default 10)."),
            "rerank": .boolean(description: "Apply reranking (slower, higher quality). Default false.")
        ],
        required: ["query"]
    )
))
```

> Note: if `ToolDefinitions` uses a different schema DSL (e.g., raw dictionaries), translate the
> property additions into that DSL. The intent is to add `source`, `project_path` as optional
> string parameters in the JSON schema, so the model can generate them in tool call arguments.

---

## Edit: Merlin/App/AppState.swift — pass projectPath in rag_search handler

```swift
// BEFORE:
toolRouter.register(name: "rag_search") { [weak self] args in
    guard let client = self?.xcalibreClient else { return "RAG unavailable." }
    return await RAGTools.search(args: args, client: client)
}

// AFTER:
toolRouter.register(name: "rag_search") { [weak self] args in
    guard let client = self?.xcalibreClient else { return "RAG unavailable." }
    let path = AppSettings.shared.projectPath
    return await RAGTools.search(
        args: args,
        client: client,
        projectPath: path.isEmpty ? nil : path
    )
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'RAGSearchTool.*passed|RAGSearchTool.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; RAGSearchToolTests → 6 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/RAG/RAGTools.swift \
        Merlin/Tools/ToolDefinitions.swift \
        Merlin/App/AppState.swift
git commit -m "Phase 111b — rag_search tool: source + project_path parameters"
```
