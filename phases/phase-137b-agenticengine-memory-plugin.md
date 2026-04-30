# Phase 137b — AgenticEngine Memory Plugin Wiring

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 137a complete: failing tests for AgenticEngine memory plugin wiring in place.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1 — Add memoryBackend property (near xcalibreClient)

Add after the existing `var xcalibreClient: (any XcalibreClientProtocol)?` property:

```swift
/// Local memory backend plugin. Receives episodic writes at session end and provides
/// memory chunk results for RAG enrichment. Defaults to NullMemoryPlugin.
/// Injected by AppState from MemoryBackendRegistry after init.
var memoryBackend: any MemoryBackendPlugin = NullMemoryPlugin()
```

### 2 — Add setMemoryBackend method

Add alongside the other setter methods (near setXcalibreClient if it exists, otherwise
near the other `set*` methods):

```swift
/// Inject the active memory backend. Called by AppState when the registry resolves
/// the active plugin.
func setMemoryBackend(_ backend: any MemoryBackendPlugin) {
    memoryBackend = backend
}
```

### 3 — Update the AgenticEngine init (if it takes xcalibreClient)

If `AgenticEngine.init` has a `xcalibreClient` parameter, add a `memoryBackend` parameter
alongside it with a default of `NullMemoryPlugin()`:

```swift
init(
    ...,
    xcalibreClient: (any XcalibreClientProtocol)? = nil,
    memoryBackend: (any MemoryBackendPlugin)? = nil,
    ...
) {
    ...
    self.xcalibreClient = xcalibreClient
    if let memoryBackend { self.memoryBackend = memoryBackend }
    ...
}
```

### 4 — Update RAG enrichment in runLoop

Locate the existing block:
```swift
var effectiveMessage = userMessage
if let client = xcalibreClient {
    let chunks = await client.searchChunks(
        query: userMessage,
        source: "all",
        ...
    )
    if !chunks.isEmpty {
        effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: chunks)
        continuation.yield(.ragSources(chunks))
    }
}
```

Replace with:
```swift
var effectiveMessage = userMessage
var ragChunks: [RAGChunk] = []

// 1. Local memory search — always runs when a backend is configured.
if let memResults = try? await memoryBackend.search(query: userMessage, topK: 5) {
    ragChunks.append(contentsOf: memResults.map { $0.toRAGChunk() })
}

// 2. xcalibre book-content search — only when xcalibre is configured.
if let client = xcalibreClient {
    let bookChunks = await client.searchChunks(
        query: userMessage,
        source: "all",
        bookIDs: nil,
        projectPath: currentProjectPath,
        limit: min(max(ragChunkLimit, 1), 20),
        rerank: ragRerank
    )
    ragChunks.append(contentsOf: bookChunks)
}

if !ragChunks.isEmpty {
    effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: ragChunks)
    continuation.yield(.ragSources(ragChunks))
}
```

### 5 — Replace xcalibre episodic write with backend write

Locate the block at end of runLoop:
```swift
if let client = xcalibreClient, AppSettings.shared.memoriesEnabled {
    if case .fail = lastCriticVerdict {
        // suppressed
    } else {
        let summary = context.messages
            .filter { $0.role == .assistant }
            .compactMap { if case .text(let t) = $0.content { return t } else { return nil } }
            .joined(separator: "\n")
            .prefix(2000)
        if !summary.isEmpty {
            _ = await client.writeMemoryChunk(
                text: String(summary),
                chunkType: "episodic",
                sessionID: ...,
                projectPath: ...,
                tags: []
            )
        }
    }
}
```

Replace with:
```swift
if AppSettings.shared.memoriesEnabled {
    if case .fail = lastCriticVerdict {
        // Critic failure — suppress episodic write to avoid polluting memory.
    } else {
        let summary = context.messages
            .filter { $0.role == .assistant }
            .compactMap { if case .text(let t) = $0.content { return t } else { return nil } }
            .joined(separator: "\n")
            .prefix(2000)
        if !summary.isEmpty {
            let chunk = MemoryChunk(
                content: String(summary),
                chunkType: "episodic",
                sessionID: sessionStore?.activeSession?.id.uuidString,
                projectPath: currentProjectPath
            )
            try? await memoryBackend.write(chunk)
        }
    }
}
```

Note: the xcalibreClient condition is removed — episodic writes now always go to the
local backend regardless of whether xcalibre is configured. The xcalibre client is
used only for book-content search (step 2 above).

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED — all 137a tests pass, zero warnings.

## Commit
```bash
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 137b — AgenticEngine: local memory plugin for writes + merged RAG search"
```
