# Phase 150a — Loop Continuation and Near-Ceiling Warning Tests

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 149b complete: LM Studio context auto-resize in place.

## Problem

When a broad task (e.g. "implement format support for CHM, LIT, SNB, PDB") is
injected into Merlin, the planner decomposes it into many steps. The executor
then tries to complete all steps in a single turn, exhausts the loop ceiling
(typically 10–30 iterations), and produces zero commits — all work is silently
dropped.

Two fixes:

**Fix 1 — Plan batching:** if `planSteps.count > maxIterations / 4`, execute
only the first batch this turn and automatically write the remaining steps as a
`[CONTINUATION]` inject. Continuation turns bypass re-classification and
re-planning and run with the high-stakes ceiling.

**Fix 2 — Near-ceiling warning:** when `loopsRemaining ≤ nearCeilingThreshold`,
inject a ⚠️ system note (visible to user) and append an urgent instruction to
the system prompt telling the LLM to commit all pending work immediately.

## New surface introduced in phase 150b

- `AgenticEngine.maxIterationsOverride: Int?` — bypasses adaptive calculation (for tests)
- `AgenticEngine.continuationInjectURL: URL` — injectable inject path (for tests)
- `AgenticEngine.nearCeilingThreshold: Int` — default 3, injectable for tests
- `AgenticEngine.nearCeilingWarningAddendum: String?` — appended to system prompt near ceiling
- `AgenticEngine.schedulePendingContinuation()` — writes `[CONTINUATION]` inject
- `isContinuation` check in `runLoop` — skips classify+decompose, uses highStakes tier

## TDD coverage

File — `MerlinTests/Unit/LoopContinuationTests.swift`:
  - `testPlanBatchSplitsAndSchedulesContinuation` — planner returns 3 steps, maxIterations=4 →
    batch note emitted, inject file written and starts with `[CONTINUATION]`, contains remaining steps
  - `testSmallPlanDoesNotScheduleContinuation` — 1 step with maxIterations=16 → no inject written
  - `testContinuationMessageSkipsDecompose` — `[CONTINUATION]` prefix → SpyPlanner.decompose not called
  - `testContinuationMessageGetsHighStakesCeiling` — continuation turn finishes without hitting ceiling
  - `testNearCeilingWarningNoteEmitted` — 2 tool calls + text, maxIterations=5, threshold=3 → ⚠️ note
  - `testNearCeilingWarningEmittedOnce` — 4 tool calls, threshold within window → exactly 1 ⚠️ note

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
# Expected: BUILD SUCCEEDED (tests compile but fail at runtime — fix in 150b)
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    -only-testing "MerlinTests/LoopContinuationTests" 2>&1 \
    | grep -E 'passed|failed'
# Expected: testPlanBatch..., testNearCeiling... FAIL; others may pass
```

## Commit
```bash
git add MerlinTests/Unit/LoopContinuationTests.swift
git commit -m "Phase 150a — LoopContinuationTests (failing)"
```
