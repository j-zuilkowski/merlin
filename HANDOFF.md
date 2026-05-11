# Codex Task: Merlin Performance Optimizations — Phases 197–199

## Objective
Implement three performance optimizations for the Merlin macOS agentic coding assistant:
(1) cache the stable portion of the system prompt so llama.cpp's KV prefix cache gets
consistent bytes across loop iterations; (2) dispatch all tool calls from a single LLM
response in one parallel batch instead of sequentially; (3) launch multiple spawn_agent
subagents concurrently and group independent plan steps into parallel batches.

All work follows strict TDD: write failing tests, commit, then implement, commit again.
Six phases total — 197a, 197b, 198a, 198b, 199a, 199b — each ends with a git commit.

## Context
- Language/Framework: Swift 5.10, macOS 14+, SwiftUI, async/await, actors
- Project root: ~/Documents/localProject/merlin
- SWIFT_STRICT_CONCURRENCY=complete — zero warnings, zero errors required
- No third-party Swift packages in production or test targets
- Non-sandboxed macOS app
- Phase files (source of truth): ~/Documents/localProject/merlin/phases/

## Key Files
- `Merlin/Engine/AgenticEngine.swift` — main agentic loop; owns system prompt, tool dispatch loop, spawn_agent handling, plan step batching
- `Merlin/Engine/PlannerEngine.swift` — PlanStep struct + decompose + parseSteps
- `TestHelpers/MockToolRouter.swift` — NEW: mock router that records dispatch() call batches
- `MerlinTests/Unit/StablePrefixCacheTests.swift` — NEW: 5 tests for phase 197
- `MerlinTests/Unit/AsyncToolDispatchTests.swift` — NEW: 4 tests for phase 198
- `MerlinTests/Unit/ParallelWorkerTests.swift` — NEW: 5 tests for phase 199

## Do NOT Touch
- `Merlin/Engine/ToolRouter.swift` — ToolRouter.dispatch() already has correct TaskGroup; no changes needed there
- Any file not listed above unless a compile error forces a minimal fix
- `project.yml` — do not add packages or targets

## Phase-by-Phase Requirements

### Phase 197a — Stable Prefix Cache Tests (failing)
Full spec: `phases/phase-197a-stable-prefix-cache-tests.md`

Write `MerlinTests/Unit/StablePrefixCacheTests.swift` exactly as specified in the phase file.
5 tests covering:
- `test_stablePrefix_isSameAcrossConsecutiveCalls`
- `test_stablePrefix_changesWhenClaudeMDContentChanges`
- `test_stablePrefix_changesWhenMemoriesContentChanges`
- `test_stablePrefix_changesWhenStandingInstructionsChange`
- `test_nearCeilingWarning_appearsInSystemPromptNotStablePrefix`

Verify BUILD FAILED (symbols don't exist yet). Commit with message:
`Phase 197a — StablePrefixCacheTests (failing)`

### Phase 197b — Stable Prefix Cache Implementation
Full spec: `phases/phase-197b-stable-prefix-cache.md`

Changes to `AgenticEngine.swift`:
1. Add `var _stablePrefixDirty = true` and `private var _stablePrefixCached = ""`
2. Add `didSet { _stablePrefixDirty = true }` to: `claudeMDContent`, `memoriesContent`, `standingInstructions`, `permissionMode`, `currentProjectPath`
3. Add internal `buildStablePrefix() -> String` with cache logic (everything except `nearCeilingWarningAddendum`)
4. Add `buildSystemPromptForTesting() -> String` (calls `buildSystemPrompt()`)
5. Rewrite `buildSystemPrompt()` to call `buildStablePrefix()` + append warning if present
6. Apply same pattern to the slot-specific `buildSystemPrompt(for slot:)` variant

Verify BUILD SUCCEEDED + all 197a tests pass. Commit:
`Phase 197b — Stable prefix cache for system prompt`

---

### Phase 198a — Async Tool Dispatch Tests (failing)
Full spec: `phases/phase-198a-async-tool-dispatch-tests.md`

Write `TestHelpers/MockToolRouter.swift` — `MockToolRouter` subclass of `ToolRouter` that
records every `dispatch()` invocation (batch call count + calls per batch).

Write `MerlinTests/Unit/AsyncToolDispatchTests.swift`. 4 tests:
- `test_multipleToolCalls_areDispatchedInOneBatch`
- `test_hookedDenialIsExcludedFromBatch`
- `test_resultsAreAppliedInOriginalCallOrder`
- `test_writeFilePaths_trackedAcrossBatch`

Tests call `engine.dispatchRegularCalls(calls, turn:loopCount:writtenFilePaths:continuation:)`
which does not exist yet — BUILD FAILED expected. Commit:
`Phase 198a — AsyncToolDispatchTests (failing)`

### Phase 198b — Async Tool Dispatch Implementation
Full spec: `phases/phase-198b-async-tool-dispatch.md`

Changes to `AgenticEngine.swift`:
1. Extract internal method `dispatchRegularCalls(_ calls: [ToolCall], turn: Int, loopCount: Int, writtenFilePaths: inout [String], continuation: AsyncStream<AgentEvent>.Continuation) async`
2. Inside it: Phase 1 = sequential pre-hooks (collect allowed/denied), Phase 2 = single `toolRouter.dispatch(allowedCalls)` call, Phase 3 = sequential context updates in original call order
3. Replace the existing `for call in regularCalls { ... toolRouter.dispatch([call]) ... }` loop with a single call to `dispatchRegularCalls(...)`

Critical: `batchResults` must be indexed in the same order as `allowedCalls` — match by
position, not by `toolCallId`, because results come back ordered by TaskGroup index.

Verify BUILD SUCCEEDED + all 198a tests pass. Commit:
`Phase 198b — Async batch tool dispatch`

---

### Phase 199a — Parallel Worker Tests (failing)
Full spec: `phases/phase-199a-parallel-worker-tests.md`

Write `MerlinTests/Unit/ParallelWorkerTests.swift`. 5 tests:
- `test_planStep_hasParallelSafeFlag`
- `test_parseSteps_readsParallelSafeAnnotation`
- `test_parseSteps_defaultsParallelSafeToFalse`
- `test_handleSpawnAgents_startsAllBeforeAnyCompletes`
- `test_parallelSafeSteps_areGroupedIntoBatch`

BUILD FAILED expected (`PlanStep.parallelSafe`, `parseStepsForTesting()`,
`handleSpawnAgents()`, `groupParallelSteps()` don't exist). Commit:
`Phase 199a — ParallelWorkerTests (failing)`

### Phase 199b — Parallel Worker Execution Implementation
Full spec: `phases/phase-199b-parallel-worker.md`

#### PlannerEngine.swift changes:
1. Add `var parallelSafe: Bool` to `PlanStep`
2. Add private `RawStep: Decodable` struct with `parallel_safe: Bool?`; parse it in `parseSteps`; default to `false` when absent
3. Add internal `parseStepsForTesting(from: String) -> [PlanStep]`
4. Update decompose prompt to include `parallel_safe` field in JSON schema instruction

#### AgenticEngine.swift changes:
1. Add `handleSpawnAgents(_ calls: [ToolCall], depth: Int, continuation: AsyncStream<AgentEvent>.Continuation) async`
   - Prepares all `SubagentEngine` instances on main actor
   - Yields `.subagentStarted` for each
   - Uses `withTaskGroup` to start all and drain their event streams concurrently
2. Replace the sequential `for call in calls { if spawn_agent { await handleSpawnAgent(...) } }` loop with:
   - Split `calls` into `spawnCalls` and `regularCalls`
   - `await handleSpawnAgents(spawnCalls, depth: depth, continuation: continuation)`
3. Add internal `groupParallelSteps(_ steps: [PlanStep], maxParallelSteps: Int = 4) -> [[PlanStep]]`
   - Adjacent parallel-safe steps merge into one batch (up to maxParallelSteps)
   - Any step with `parallelSafe == false` is always its own batch
4. Replace the `stepsPerTurn = 1` split logic with `groupParallelSteps`; use the first batch as `thisBatch`; flatten remaining batches back to `pendingContinuationSteps`
5. When `thisBatch.count > 1`, inject a parallel-task prompt so the model uses `spawn_agent` for each step

Verify BUILD SUCCEEDED + all 199a tests pass. Commit:
`Phase 199b — Parallel worker execution (spawn_agent + plan batching)`

---

## Acceptance Criteria
- [ ] BUILD SUCCEEDED with zero warnings, zero errors after each b-phase
- [ ] All 197a tests pass after 197b
- [ ] All 198a tests pass after 198b
- [ ] All 199a tests pass after 199b
- [ ] Full test suite passes (no regressions): `xcodebuild -scheme MerlinTests test`
- [ ] Exactly 6 git commits created (197a, 197b, 198a, 198b, 199a, 199b)
- [ ] No modifications to ToolRouter.swift, project.yml, or files outside the listed set

## Build Commands (use exactly these)
```bash
# Build for testing
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Run tests
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

## Additional Notes
- `AgenticEngine` is `@MainActor final class` — `withTaskGroup` child tasks for spawn agents must capture only `Sendable` values (`SubagentEngine` is an actor; `AsyncStream.Continuation` is Sendable)
- `ToolRouter` is `@MainActor class` — do not restructure its internals; only change how `AgenticEngine` calls `dispatch()`
- `HookEngine` is an `actor` — `runPreToolUse` and `runPostToolUse` are safe to await from any context
- `_stablePrefixDirty` and `_stablePrefixCached` use the underscore prefix intentionally (internal test access without the `private` restriction)
- The `context` variable inside `runLoop()` is a local alias for `contextManager` — verify the alias name before referencing it in `dispatchRegularCalls`; pass it as a parameter if needed
- Commit message format exactly: `Phase NNx — <Description>` (no trailing period)
