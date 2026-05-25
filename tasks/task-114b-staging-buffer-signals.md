# Phase 114b — StagingBuffer OutcomeSignals Wiring

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 114a complete: StagingBufferSignalsTests (failing) in place.

---

## Edit: Merlin/Engine/StagingBuffer.swift — add outcome counters

Add private counters and reset method:

```swift
actor StagingBuffer {
    // ... existing properties ...

    // MARK: - Session outcome counters
    // Reset at the start of each runLoop turn via resetSessionCounts().
    // Read by AgenticEngine at session end to populate OutcomeSignals.

    private(set) var acceptedCount: Int = 0
    private(set) var rejectedCount: Int = 0
    private(set) var editedOnAcceptCount: Int = 0

    func resetSessionCounts() {
        acceptedCount = 0
        rejectedCount = 0
        editedOnAcceptCount = 0
    }
```

Update `accept(_ id:)` to increment counters:
```swift
// BEFORE:
func accept(_ id: UUID) async throws {
    guard let index = pendingChanges.firstIndex(where: { $0.id == id }) else { return }
    let change = pendingChanges[index]
    try applyChange(change)
    pendingChanges.remove(at: index)
    removeHistoryEntry(matching: change)
}

// AFTER:
func accept(_ id: UUID) async throws {
    guard let index = pendingChanges.firstIndex(where: { $0.id == id }) else { return }
    let change = pendingChanges[index]
    try applyChange(change)
    pendingChanges.remove(at: index)
    removeHistoryEntry(matching: change)
    acceptedCount += 1
    if !change.comments.isEmpty { editedOnAcceptCount += 1 }
}
```

Update `reject(_ id:)`:
```swift
// AFTER:
func reject(_ id: UUID) {
    guard let index = pendingChanges.firstIndex(where: { $0.id == id }) else { return }
    let change = pendingChanges.remove(at: index)
    removeHistoryEntry(matching: change)
    rejectedCount += 1
}
```

Update `acceptAll()`:
```swift
// AFTER:
func acceptAll() async throws {
    for change in pendingChanges {
        try applyChange(change)
        removeHistoryEntry(matching: change)
        acceptedCount += 1
        if !change.comments.isEmpty { editedOnAcceptCount += 1 }
    }
    pendingChanges.removeAll()
}
```

Update `rejectAll()`:
```swift
// AFTER:
func rejectAll() {
    rejectedCount += pendingChanges.count
    for change in pendingChanges {
        removeHistoryEntry(matching: change)
    }
    pendingChanges.removeAll()
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift — read counters into OutcomeSignals

At the start of `runLoop`, reset the staging buffer counters for this turn:
```swift
// After: let domain = await DomainRegistry.shared.activeDomain()
// Add:
if let buffer = toolRouter.stagingBuffer {
    await buffer.resetSessionCounts()
}
```

At session end, replace the hardcoded OutcomeSignals:
```swift
// BEFORE:
let signals = OutcomeSignals(
    stage1Passed: nil,
    stage2Score: nil,
    diffAccepted: true,
    diffEditedOnAccept: false,
    criticRetryCount: 0,
    userCorrectedNextTurn: false,
    sessionCompleted: true,
    addendumHash: await currentAddendumHash(for: workingSlot)
)

// AFTER:
let stagingAccepted = await toolRouter.stagingBuffer?.acceptedCount ?? 0
let stagingRejected = await toolRouter.stagingBuffer?.rejectedCount ?? 0
let stagingEdited   = await toolRouter.stagingBuffer?.editedOnAcceptCount ?? 0

let signals = OutcomeSignals(
    stage1Passed: nil,
    stage2Score: nil,
    // diffAccepted: true if nothing was staged (no file changes), or something was accepted
    // diffAccepted: false only if changes were staged and ALL were rejected
    diffAccepted: stagingRejected == 0 || stagingAccepted > 0,
    diffEditedOnAccept: stagingEdited > 0,
    criticRetryCount: 0,
    userCorrectedNextTurn: false,
    sessionCompleted: true,
    addendumHash: await currentAddendumHash(for: workingSlot)
)
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'StagingBuffer.*passed|StagingBuffer.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; StagingBufferSignalsTests → 9 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/StagingBuffer.swift \
        Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 114b — StagingBuffer accept/reject wired into OutcomeSignals (diffAccepted, diffEditedOnAccept)"
```
