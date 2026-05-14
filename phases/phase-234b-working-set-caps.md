# Phase 234b — Working-Set Caps

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 234a complete: failing tests for the WorkingSetBudget allocator, per-component truncation,
post-tool-burst compaction, and end-to-end pre-flight integration.

After this phase, the four context components (system prompt, RAG injection, recent turns, tool
burst) each carry their own ceiling derived from the active `ProviderBudget`. Compaction fires
when *a component* runs hot, not only when the whole context crosses a global threshold. This
is the change that makes "seamless regardless of provider" structurally true rather than
aspirational.

---

## Edit

- `Merlin/Engine/WorkingSetBudget.swift` — new file. Allocator splits `usableInputTokens` as
  documented in 234a's "New surface" block. Enforce a 256-token floor per component; when the
  budget is too small to satisfy all four floors, log a warning via `TelemetryEmitter` event
  `engine.workingset.budget_too_small` and use proportional floors.
- `Merlin/Engine/ContextManager.swift`:
    - `applyWorkingSetCaps(_:)` — async. Order of truncation when over: (1) compact tool exchanges
      via existing summary path, (2) drop oldest recent turns, (3) trim RAG chunks by count then
      length, (4) last resort: truncate system prompt with a single `[truncated for budget]` marker.
    - `compactAfterToolBurst()` — async. Estimates current tool-burst component (sum of tool-call
      assistant messages + their tool results since the last user message). If over cap, runs
      summary compaction restricted to the tool-burst region.
    - Move the existing `_ = await context.compactWithSummaryIfNeeded(provider:)` invocation at
      AgenticEngine.swift:1046 to call `compactAfterToolBurst()` instead. The old method stays
      for the pre-flight fallback path.
- `Merlin/Engine/AgenticEngine.swift`:
    - `applyWorkingSetCapsBeforeSend(...)` — invoked inside `preflightCheck` from 233b before the
      estimator's overflow decision. Pulls budget, derives caps, calls
      `context.applyWorkingSetCaps(caps)`, re-estimates. Order: caps → estimate → if still over,
      summary-compact → estimate → if still over, throw `EngineError.preflightOverflow`.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 234a tests pass. No prior phase regresses.

## Commit

```bash
git add phases/phase-234b-working-set-caps.md \
    Merlin/Engine/WorkingSetBudget.swift \
    Merlin/Engine/ContextManager.swift \
    Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 234b — Working-set caps (per-component budget enforcement)"
```

## PASTE-LIST update

Append phase 234a/234b under the "Budget-Aware Execution (v2.1.0)" section.
