# Phase 169b — Continuation Abort Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 169a complete: ContinuationAbortTests (failing) in place.

## Root Cause

When Merlin decomposes a task into N plan steps (`stepsPerTurn = 1`), it schedules N-1
continuation turns by writing to `continuationInjectURL`. If the model completes all N
steps inside a single turn (going beyond the `stepsPerTurn` budget), the engine still
has N-1 entries in `pendingContinuationSteps` — it has no signal that the model finished
early — and writes every one of them to inject.txt. Each continuation turn then tries to
re-execute an already-done step, leading to double-application of changes and the
"critic max retries exhausted" halt.

## Fix

Two targeted edits to `Merlin/Engine/AgenticEngine.swift`:

### 1. `schedulePendingContinuation()` — append abort instruction

Append to the injected `[CONTINUATION]` message:

```
If this step is already complete, respond with [STEP_ALREADY_DONE] and take no further action.
```

### 2. `runLoop` — detect abort signal and suppress next scheduling

After accumulating `fullText` for each provider response and before the post-turn hook,
detect `[STEP_ALREADY_DONE]` in the response **only during continuation turns**
(`isContinuation == true`). When detected:

- Set `continuationAborted = true` (private `Bool` property, reset to `false` at the
  start of every turn).
- Call `pendingContinuationSteps.removeAll()`.
- Emit a `.systemNote` so the user sees: `"↩︎ Continuation step already done — remaining steps cancelled."`.

In the post-turn hook (after the main loop exits):

```swift
if !pendingContinuationSteps.isEmpty && !continuationAborted {
    schedulePendingContinuation()
}
```

Replace the existing unconditional check:

```swift
// OLD
if !pendingContinuationSteps.isEmpty {
    schedulePendingContinuation()
}

// NEW
if !pendingContinuationSteps.isEmpty && !continuationAborted {
    schedulePendingContinuation()
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### New property (add near other loop-state properties, ~line 51)

```swift
private var continuationAborted: Bool = false   // set when [STEP_ALREADY_DONE] detected
```

### In `runLoop` — reset flag at turn start (add after `isContinuation` is set, ~line 530)

```swift
continuationAborted = false
```

### In `runLoop` — detect abort signal after fullText is assembled (~line 815, inside the `if !fullText.isEmpty` block, after appending to context)

```swift
// Continuation abort: if the model signals the step is already done, clear
// the pending queue so no further continuation turns are scheduled.
// Also delete the inject file so no stale [CONTINUATION] can fire from disk.
if isContinuation && fullText.contains("[STEP_ALREADY_DONE]") {
    continuationAborted = true
    pendingContinuationSteps.removeAll()
    try? FileManager.default.removeItem(at: continuationInjectURL)
    continuation.yield(.systemNote(
        "↩︎ Continuation step already done — remaining steps cancelled."
    ))
}
```

### In post-turn hook — guard scheduling with abort flag (~line 1154)

```swift
// Fix 1: If this turn processed a batch-split plan, write the remaining steps
// as a [CONTINUATION] inject so the engine picks them up automatically.
// Abort guard: if the model signalled [STEP_ALREADY_DONE], skip scheduling
// so no further continuation turns fire for already-completed work.
if !pendingContinuationSteps.isEmpty && !continuationAborted {
    schedulePendingContinuation()
}
```

### In `schedulePendingContinuation()` — append abort instruction (~line 1188)

```swift
let message = """
[CONTINUATION] Steps 1–\(completedCount) of the following task are complete. \
Execute the next \(thisBatch.count) step(s) now:
\(stepList)

Original task: \(originalTask)
If this step is already complete, respond with [STEP_ALREADY_DONE] and take no further action.
"""
```

---

## Also update: phases/phase-17c-agenticengine-v5-addendum.md

Add `continuationAborted` to the **Loop state** properties table:

```swift
private var continuationAborted: Bool = false   // suppresses schedulePendingContinuation() after [STEP_ALREADY_DONE]
```

And document the abort detection in the **`runLoop` Extensions** section under a new
point **19. Continuation abort detection**:

```
### 19. Continuation abort detection

When `isContinuation == true` and `fullText.contains("[STEP_ALREADY_DONE]")`:
- Sets `continuationAborted = true`
- Calls `pendingContinuationSteps.removeAll()`
- Emits `.systemNote("↩︎ Continuation step already done — remaining steps cancelled.")`
- Post-turn hook skips `schedulePendingContinuation()` when `continuationAborted` is set

`continuationAborted` is reset to `false` at the start of every turn so it is not
sticky across independent messages.

`schedulePendingContinuation()` always appends the abort instruction to the injected
message so the model knows it may emit `[STEP_ALREADY_DONE]`.
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED; all 6 `ContinuationAbortTests` pass; all prior tests pass.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        phases/phase-169b-continuation-abort.md \
        phases/phase-17c-agenticengine-v5-addendum.md
git commit -m "Phase 169b — Continuation abort: [STEP_ALREADY_DONE] clears pending queue"
```
