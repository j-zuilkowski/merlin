# Phase diag-04b — Memory & RAG Telemetry Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-04a complete: failing tests in place.

Instrument `MemoryEngine` and `XcalibreClient` with telemetry events.

---

## Edit: Merlin/Memories/MemoryEngine.swift

### 1. Instrument `generateMemories(from:)`

Find the function signature:
```swift
    func generateMemories(from messages: [Message]) async throws -> [MemoryEntry] {
```

At the **top** of the function body, add:
```swift
        TelemetryEmitter.shared.emit("memory.generate.start", data: [
            "message_count": TelemetryValue.int(messages.count)
        ])
        let generateStart = Date()
```

Wrap the existing function body in a `do/catch`:
```swift
        do {
            // ... existing implementation ...
            let entries = /* result of existing logic */
            let ms = Date().timeIntervalSince(generateStart) * 1000
            TelemetryEmitter.shared.emit("memory.generate.complete", durationMs: ms, data: [
                "entry_count": TelemetryValue.int(entries.count)
            ])
            return entries
        } catch {
            let ms = Date().timeIntervalSince(generateStart) * 1000
            TelemetryEmitter.shared.emit("memory.generate.error", durationMs: ms, data: [
                "error_domain": TelemetryValue.string((error as NSError).domain),
                "error_code":   TelemetryValue.int((error as NSError).code)
            ])
            throw error
        }
```

### 2. Instrument `sanitize(_:)`

Find:
```swift
    func sanitize(_ text: String) async -> String {
```

At the top of the body, add:
```swift
        let inputBytes = text.utf8.count
        let sanitizeStart = Date()
```

Just before the `return` statement, add:
```swift
        let ms = Date().timeIntervalSince(sanitizeStart) * 1000
        TelemetryEmitter.shared.emit("memory.sanitize", durationMs: ms, data: [
            "input_bytes":  TelemetryValue.int(inputBytes),
            "output_bytes": TelemetryValue.int(result.utf8.count)
        ])
```

(where `result` is the sanitized string being returned — rename the return variable if needed)

---

## Edit: Merlin/RAG/XcalibreClient.swift

### 1. Instrument `searchChunks(...)`

Find the function:
```swift
    func searchChunks(
        query: String,
        source: String = "books",
        bookIDs: [String]? = nil,
        projectPath: String? = nil,
```

At the top of the function body, add:
```swift
        TelemetryEmitter.shared.emit("rag.search.start", data: [
            "query_length": TelemetryValue.int(query.count),
            "source":       TelemetryValue.string(source),
            "limit":        TelemetryValue.int(limit)
        ])
        let searchStart = Date()
```

Wrap the existing fetch+decode logic in a `do/catch`:
```swift
        do {
            // ... existing implementation that produces chunks ...
            let ms = Date().timeIntervalSince(searchStart) * 1000
            TelemetryEmitter.shared.emit("rag.search.complete", durationMs: ms, data: [
                "result_count": TelemetryValue.int(chunks.count)
            ])
            return chunks
        } catch {
            let ms = Date().timeIntervalSince(searchStart) * 1000
            TelemetryEmitter.shared.emit("rag.search.error", durationMs: ms, data: [
                "error_domain": TelemetryValue.string((error as NSError).domain),
                "error_code":   TelemetryValue.int((error as NSError).code)
            ])
            return []
        }
```

### 2. Instrument `searchMemory(...)`

Find:
```swift
    func searchMemory(query: String, projectPath: String? = nil, limit: Int = 10) async -> [RAGChunk] {
```

At the top of the body, add:
```swift
        let memSearchStart = Date()
```

After the result is produced, before returning, add:
```swift
        let ms = Date().timeIntervalSince(memSearchStart) * 1000
        TelemetryEmitter.shared.emit("rag.memory.search", durationMs: ms, data: [
            "query_length": TelemetryValue.int(query.count),
            "result_count": TelemetryValue.int(results.count)
        ])
```

### 3. Instrument `writeMemoryChunk(...)`

Find:
```swift
    func writeMemoryChunk(
```

At the top of the body, add:
```swift
        let writeStart = Date()
```

After the write completes (success or failure), add:
```swift
        let ms = Date().timeIntervalSince(writeStart) * 1000
        TelemetryEmitter.shared.emit("rag.memory.write", durationMs: ms, data: [
            "chunk_bytes": TelemetryValue.int(content.utf8.count)
        ])
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'MemoryTelemetry|RAGTelemetry|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all MemoryTelemetryTests and RAGTelemetryTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git add Merlin/Memories/MemoryEngine.swift \
        Merlin/RAG/XcalibreClient.swift
git commit -m "Phase diag-04b — Memory & RAG telemetry instrumentation"
```
