# Task 205b — Mid-loop Compaction

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 205a complete: failing ContextManagerMidLoopCompactionTests.

See also: FEATURES.md § "Prompt Compression — Mid-loop compaction"
Reference: https://machinelearningmastery.com/implementing-prompt-compression-to-reduce-agentic-loop-costs/

---

## Edit: Merlin/Engine/ContextManager.swift

### 1. Add `midLoopCompactionThreshold` property

After the existing `let preRunCompactionThreshold = 10_000` line, add:

```swift
/// Token threshold that triggers compaction mid-loop, inside the `while true` execute loop.
/// A `var` so tests can lower it without mocking. Default: 40 000 tokens —
/// well below a typical 32 K model context, giving the next LLM call ample output headroom.
var midLoopCompactionThreshold: Int = 40_000
```

### 2. Add `compactIfNeededMidLoop()` method

After `compactIfNeededBeforeRun(isContinuation:)`, add:

```swift
/// Called inside the `while true` execute loop after every tool-dispatch round.
/// Compacts when accumulated tool results push the context past `midLoopCompactionThreshold`,
/// keeping per-turn token cost linear regardless of how many tool iterations the loop takes.
/// Skipped when at or below threshold — no-op cost.
func compactIfNeededMidLoop() {
    guard estimatedTokens > midLoopCompactionThreshold else { return }
    compact(force: true)
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 3. Call `compactIfNeededMidLoop()` at the bottom of the `while true` body

Locate `dispatchRegularCalls(...)` inside the `while true` loop (currently the last call before the loop
iterates). Immediately **after** both `handleSpawnAgents` and `dispatchRegularCalls` return — and before the
loop goes back to its top — add:

```swift
// Prompt compression: compact if tool results have pushed tokens past the mid-loop threshold.
// Task 206 will replace this with an async LLM-summarisation call.
context.compactIfNeededMidLoop()
emitCompactionNoteIfNeeded()
```

The surrounding context looks like this after the change:

```swift
await handleSpawnAgents(spawnCalls, depth: depth, continuation: continuation)
await dispatchRegularCalls(
    regularCalls,
    turn: turn,
    loopCount: loopCount,
    writtenFilePaths: &writtenFilePaths,
    continuation: continuation,
    context: context,
    emitCompactionNoteIfNeeded: emitCompactionNoteIfNeeded
)
// Prompt compression: compact if tool results have pushed tokens past the mid-loop threshold.
// Task 206 will replace this with an async LLM-summarisation call.
context.compactIfNeededMidLoop()
emitCompactionNoteIfNeeded()
```

No other changes to `AgenticEngine.swift`.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED. All `ContextManagerMidLoopCompactionTests` pass. No regressions in existing compaction tests (`ContextCompactionTests`, `ContextPreRunCompactionTests`, `SkillCompactionTests`, `ContextCompactionTelemetryTests`, `EnginePreRunCompactionIntegrationTests`).

Manual verification during an agentic run:
1. Start a long tool-calling session (e.g. read many files).
2. After enough tool results accumulate, a `[context compacted]` system note appears mid-session without the user requesting it.
3. The session continues normally after compaction.

## Commit

```bash
git add Merlin/Engine/ContextManager.swift \
        Merlin/Engine/AgenticEngine.swift
git commit -m "Task 205b — mid-loop compaction: compact at 40k tokens inside the execute loop"
```
