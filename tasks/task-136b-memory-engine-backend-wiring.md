# Phase 136b — MemoryEngine Backend Wiring

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 136a complete: failing tests for MemoryEngine backend wiring in place.

---

## Edit: Merlin/Memories/MemoryEngine.swift

Remove `xcalibreClient` and `setXcalibreClient(_:)` entirely.
Add `memoryBackend` (any MemoryBackendPlugin) defaulting to NullMemoryPlugin.
Add `setMemoryBackend(_:)`.
Update `approve(_:movingTo:)` to write to the backend instead of xcalibre.

Diff:

1. Remove the property:
   ```swift
   // DELETE:
   private var xcalibreClient: (any XcalibreClientProtocol)?
   ```
   Replace with:
   ```swift
   private var memoryBackend: any MemoryBackendPlugin = NullMemoryPlugin()
   ```

2. Remove the method:
   ```swift
   // DELETE:
   func setXcalibreClient(_ client: any XcalibreClientProtocol) {
       xcalibreClient = client
   }
   ```
   Replace with:
   ```swift
   /// Inject the active memory backend. Called by AppState after the registry
   /// resolves the active plugin. Defaults to NullMemoryPlugin.
   func setMemoryBackend(_ backend: any MemoryBackendPlugin) {
       memoryBackend = backend
   }
   ```

3. Replace the xcalibre block at the bottom of `approve(_:movingTo:)`:
   ```swift
   // DELETE this block:
   guard let xcalibreClient else { return }
   guard let content = try? String(contentsOf: destination, encoding: .utf8) else { return }
   _ = await xcalibreClient.writeMemoryChunk(
       text: content,
       chunkType: "factual",
       sessionID: nil,
       projectPath: nil,
       tags: ["session-memory"]
   )
   ```
   Replace with:
   ```swift
   guard let content = try? String(contentsOf: destination, encoding: .utf8),
         !content.isEmpty else { return }
   let chunk = MemoryChunk(
       content: content,
       chunkType: "factual",
       tags: ["session-memory"]
   )
   try? await memoryBackend.write(chunk)
   ```

The final `approve(_:movingTo:)` should look like:
```swift
func approve(_ url: URL, movingTo acceptedDir: URL) async throws {
    try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
    let destination = acceptedDir.appendingPathComponent(url.lastPathComponent)
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: url, to: destination)

    guard let content = try? String(contentsOf: destination, encoding: .utf8),
          !content.isEmpty else { return }
    let chunk = MemoryChunk(
        content: content,
        chunkType: "factual",
        tags: ["session-memory"]
    )
    try? await memoryBackend.write(chunk)
}
```

Also check `Merlin/UI/Memories/MemoryReviewView.swift` — it previously called
`engine.setXcalibreClient(...)`. Update it to call `engine.setMemoryBackend(...)` using
the `AppState.memoryRegistry.activePlugin` instead. If `MemoryReviewView` receives
an `AppState` via environment, use:
```swift
await engine.setMemoryBackend(appState.memoryRegistry.activePlugin)
```
(AppState.memoryRegistry is added in phase 138b; for now, inject NullMemoryPlugin or
use the registry if it is available, depending on what MemoryReviewView has access to.)

If `MemoryReviewView` currently calls `setXcalibreClient`, remove that call and do not
replace it yet — the AppState wiring from phase 138b will inject the correct backend.
The NullMemoryPlugin default in MemoryEngine means approve() will still function
(just without persistence) until 138b completes the wiring.

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED — all 136a tests pass, zero warnings.
Check that no other file still calls `engine.setXcalibreClient` (grep the codebase first).

## Commit
```bash
git add Merlin/Memories/MemoryEngine.swift
# Also add MemoryReviewView.swift if it was changed:
# git add Merlin/UI/Memories/MemoryReviewView.swift
git commit -m "Phase 136b — MemoryEngine: replace xcalibre write with MemoryBackendPlugin"
```
