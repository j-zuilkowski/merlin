# Phase 320b — Wire WorkerDiffView Reject-All / Accept-and-Merge

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 320a complete: failing `WorkerDiffViewActionTests` in place.

W4 trace audit finding F1: `WorkerDiffView`'s "Reject All" and "Accept & Merge" toolbar
buttons have empty `{ }` actions — dead controls. This phase adds two `async` methods and
wires the buttons to them.

`StagingBuffer` API used (from `Merlin/Engine/StagingBuffer.swift`):
- `func rejectAll()` — actor-isolated, synchronous; discards all `pendingChanges` and
  their history entries.
- `func acceptAll() async throws` — actor-isolated; applies every `pendingChanges` entry
  to disk, then clears the buffer.

`loadEntries()` (already private on `WorkerDiffView`) re-reads `entry.stagingBuffer` into
the displayed `stagingEntries` list — call it after each action so the UI refreshes.

---

## Edit: Merlin/UI/Sidebar/WorkerDiffView.swift

**1.** Replace the two empty-action buttons in the `.toolbar` block. Change:
```swift
                Button("Reject All") { }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityID.workerDiffRejectAllButton)
                Button("Accept & Merge") { }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.workerDiffAcceptMergeButton)
```
to:
```swift
                Button("Reject All") {
                    Task { await rejectAllChanges() }
                }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityID.workerDiffRejectAllButton)
                Button("Accept & Merge") {
                    Task { await acceptAndMergeChanges() }
                }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.workerDiffAcceptMergeButton)
```

**2.** Add the two action methods immediately after the existing `loadEntries()` method
(keep them non-`private` — `WorkerDiffViewActionTests` calls them):
```swift
    func rejectAllChanges() async {
        if let buffer = entry.stagingBuffer {
            await buffer.rejectAll()
        }
        await loadEntries()
    }

    func acceptAndMergeChanges() async {
        if let buffer = entry.stagingBuffer {
            try? await buffer.acceptAll()
        }
        await loadEntries()
    }
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/WorkerDiffViewActionTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:|warning:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: both `WorkerDiffViewActionTests` pass; BUILD SUCCEEDED on both schemes, zero
warnings. The discipline `StubMarkerScanner` no longer flags `WorkerDiffView.swift`.

## Commit
```
git add Merlin/UI/Sidebar/WorkerDiffView.swift phases/phase-320b-worker-diff-actions.md
git commit -m "Phase 320b — Wire WorkerDiffView reject-all / accept-and-merge"
```
