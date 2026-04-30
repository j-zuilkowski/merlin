# Phase 122b — Memory Xcalibre Index Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 122a complete: failing tests added for approved-memory xcalibre indexing.

Phase 122a introduced these expectations:
  - `MemoryEngine.setXcalibreClient(_ client: any XcalibreClientProtocol)`
  - `MemoryEngine.approve(_:movingTo:)` writes approved memory content to xcalibre as a factual chunk

Implementation notes:
  - `MemoryEngine` now stores an optional xcalibre client and writes approved memory files to xcalibre after moving them into the accepted directory.
  - Approved writes use chunk type `"factual"` and include the `"session-memory"` tag.
  - The memory review UI passes the current app xcalibre client into `MemoryEngine` before approving a file so the feature is active in the app.

---

## Write to / Edit

### `Merlin/Memories/MemoryEngine.swift`
- Added xcalibre client storage and `setXcalibreClient(_:)`.
- Extended `approve(_:movingTo:)` to move the file first, then write its contents to xcalibre with factual/session-memory metadata.

### `Merlin/UI/Memories/MemoryReviewView.swift`
- Pulls the current `AppState` xcalibre client from environment and injects it into `MemoryEngine` before approving.

### `Merlin/Views/WorkspaceView.swift`
- Passes the active session app state into the memory review sheet so the review UI can access the xcalibre client in workspace windows.

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, with the new 122a tests passing.

## Commit
git add Merlin/Memories/MemoryEngine.swift Merlin/UI/Memories/MemoryReviewView.swift Merlin/Views/WorkspaceView.swift phases/phase-122b-memory-xcalibre-index.md
git commit -m "Phase 122b — MemoryXcalibreIndex"
