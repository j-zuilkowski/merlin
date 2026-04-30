# Phase 122b — Memory Xcalibre Index Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 122a complete: 6 failing tests in MemoryXcalibreIndexTests.

Design intent:
  Accepted AI-generated memories currently land in `~/.merlin/memories/` as Markdown files
  and are injected as a verbatim system prompt block each session. This phase adds a second
  path: on approval the file content is written to xcalibre-server as a `"factual"` chunk
  (chunkType "factual", tags ["session-memory"], projectPath nil) so it is queryable by RAG
  and only surfaces when relevant — rather than always being prepended to the system prompt.

  The existing verbatim injection path is unchanged. Both paths run together.

Files to edit:
  1. `Merlin/Memories/MemoryEngine.swift` — add xcalibreClient property + write in approve()
  2. `Merlin/UI/Memories/MemoryReviewView.swift` — accept xcalibreClient and set on engine

---

## Edit: Merlin/Memories/MemoryEngine.swift

Add a stored property and a setter immediately after the existing stored properties, and
extend `approve()` to read the moved file and write it to xcalibre.

### Change 1 — Add stored property (after `private var onIdleFired` line)

```swift
// Before:
actor MemoryEngine {
    private var idleTask: Task<Void, Never>?
    private var timeout: TimeInterval = 300
    private var onIdleFired: (@Sendable () -> Void)?
    private var provider: (any LLMProvider)?

// After:
actor MemoryEngine {
    private var idleTask: Task<Void, Never>?
    private var timeout: TimeInterval = 300
    private var onIdleFired: (@Sendable () -> Void)?
    private var provider: (any LLMProvider)?
    /// Injected xcalibre client. When set, approved memories are also indexed as RAG chunks.
    private var xcalibreClient: (any XcalibreClientProtocol)?
```

### Change 2 — Add setter (after `func setProvider`)

```swift
    func setXcalibreClient(_ client: any XcalibreClientProtocol) {
        xcalibreClient = client
    }
```

### Change 3 — Extend approve() to write to xcalibre after moving

Replace the existing `approve` implementation:

```swift
// Before:
    func approve(_ url: URL, movingTo acceptedDir: URL) async throws {
        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
        let destination = acceptedDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
    }

// After:
    func approve(_ url: URL, movingTo acceptedDir: URL) async throws {
        // Read content before moving (URL will change).
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
        let destination = acceptedDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)

        // Index into xcalibre-server as a factual chunk so the memory surfaces via RAG queries.
        // A nil return value (write failed / xcalibre unavailable) is silently ignored —
        // the file has already been moved to the accepted directory.
        if !content.isEmpty, let client = xcalibreClient {
            _ = await client.writeMemoryChunk(
                text: content,
                chunkType: "factual",
                sessionID: nil,
                projectPath: nil,
                tags: ["session-memory"]
            )
        }
    }
```

---

## Edit: Merlin/UI/Memories/MemoryReviewView.swift

`MemoryReviewView` creates its own `MemoryEngine` instance. Wire the xcalibre client from
the call site so the engine can write to xcalibre on approval.

### Change 1 — Add xcalibreClient property to the view

```swift
// Before:
struct MemoryReviewView: View {
    @State private var pendingURLs: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewContent: String = ""

    private let engine = MemoryEngine()

// After:
struct MemoryReviewView: View {
    /// Optional xcalibre client injected by the parent. When set, approved memories are
    /// indexed as RAG chunks in addition to being moved to the accepted directory.
    var xcalibreClient: (any XcalibreClientProtocol)?

    @State private var pendingURLs: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewContent: String = ""

    private let engine = MemoryEngine()
```

### Change 2 — Wire client on task start

Add a `.task` modifier that sets the xcalibre client on the engine. Append this after the
existing `.task { await refresh() }` modifier:

```swift
        .task {
            if let client = xcalibreClient {
                await engine.setXcalibreClient(client)
            }
        }
```

Note: The view already has `.task { await refresh() }`. Add the new `.task` block directly
after it. Both tasks run concurrently on appear — the order does not matter because approval
actions only happen after user interaction, well after both tasks complete.

---

## Wire in AppState / Settings

Find where `MemoryReviewView()` is instantiated (likely in `MemorySettingsSection.swift` or
a settings tab view). Pass the xcalibre client from `AppState`:

```swift
// Before:
MemoryReviewView()

// After:
MemoryReviewView(xcalibreClient: appState.xcalibreClient)
```

`appState.xcalibreClient` is typed as `XcalibreClient` which already conforms to
`XcalibreClientProtocol` via the extension in `XcalibreClientProtocol.swift`.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD SUCCEEDED** — all 122a tests pass; total test count increases by 6; all prior tests pass.

## Commit
```bash
git add Merlin/Memories/MemoryEngine.swift
git add Merlin/UI/Memories/MemoryReviewView.swift
git commit -m "Phase 122b — approved memories indexed in xcalibre-server as factual RAG chunks"
```
