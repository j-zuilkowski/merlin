# Phase 237a — Unified Executor Gate + Recovery Deletion Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 236b complete: enriched `PlanStep` and `PlannerEngine.refineStep` available; not yet
consumed by the executor.

This is the load-bearing phase of the v2.1.0 series. It does three things together because they
share an invariant ("no unbounded retry path in the engine"):
  1. Consolidates the ReAct iteration-ceiling logic, the recursive context-overrun recovery,
     and ad-hoc retry counters behind one `EscalationHandler.escalateOrStop(...)` helper.
  2. Deletes the recursive `runLoop(...)` self-call at `AgenticEngine.swift:1076`. The infinite
     looping observed in prior context-overrun handling is structurally impossible after this
     phase because no code path re-enters `runLoop` from inside its own catch block.
  3. Wires the ReAct iteration ceiling to call `PlannerEngine.refineStep(reason: .iterationCap)`
     via the same helper.

New surface introduced in phase 237b:
  - `Merlin/Engine/EscalationHandler.swift` — single retry/escalation policy.
    ```swift
    enum EscalationReason: Sendable {
        case iterationCap(loopCount: Int, lastObservation: String)
        case preflightOverflow(estimated: Int, budget: Int)
    }
    enum EscalationDecision: Sendable {
        case continueWith(replacementSteps: [PlanStep])
        case stop(message: String)
    }
    actor EscalationHandler {
        init(planner: PlannerEngine, maxRefinementsPerTurn: Int = 2)
        func escalateOrStop(currentStep: PlanStep, reason: EscalationReason,
                            context: [Message]) async -> EscalationDecision
    }
    ```
    `escalateOrStop` calls `planner.refineStep(...)`. If `.decomposed` → `.continueWith(...)`.
    If `.cannotDecompose` → `.stop(message:)` with a structured human-readable explanation.
    Bounded by `maxRefinementsPerTurn` — once exceeded, any further call returns
    `.stop(message: "refinement budget exhausted")`.
  - `AgenticEngine.handleEscalation(...)` private method invoked from two sites:
      1. When `loopCount` reaches the existing `nearCeilingThreshold` ([:788](AgenticEngine.swift:788))
         and the loop is making no progress (no new tool calls or text in the last 3 iterations),
         call `escalateOrStop(reason: .iterationCap)` and act on the decision.
      2. When `preflightCheck` throws `EngineError.preflightOverflow`, call
         `escalateOrStop(reason: .preflightOverflow)` and act on the decision. This *replaces*
         the recursive `runLoop` call in the existing `catch let pe as ProviderError where
         pe.isContextLengthExceeded` block.
  - `AgenticEngine.runLoop` no longer self-recurses. The recursive call site at
    `AgenticEngine.swift:1076` is **deleted**. The block that catches
    `ProviderError.isContextLengthExceeded` is reduced to: log + emit telemetry + emit a
    `.systemNote` ("context overrun — last-ditch compaction") + one summary-compaction attempt;
    if still over → call `handleEscalation`. No retry counters survive (`contextLengthRetryCount`,
    `maxContextOverrunRecoveryAttempts` are removed).
  - "Graceful stop" structured outcome emitted as a `.systemNote` of the form
    `"⛔ Cannot continue: <reason>. Suggested: <suggestion>. Progress so far: <bullet summary>."`
    plus a new event type yielded on the AsyncStream: `.cleanStop(reason: String, summary: String)`.
    UI consumers currently render `.systemNote` — `.cleanStop` is forward-looking for
    distinct UI affordance.

TDD coverage:
  File 1 — `MerlinTests/Unit/EscalationHandlerTests.swift`: `.iterationCap` triggers planner
    refinement, returns `.continueWith` when planner decomposes, returns `.stop` when planner
    answers `.cannotDecompose`. Refinement budget cap fires after N successful refinements.
  File 2 — `MerlinTests/Unit/RunLoopNoRecursionTests.swift`: under a context-overrun scenario
    (provider mocked to throw `.isContextLengthExceeded` once), `runLoop` completes in a single
    invocation — instrumented to count recursive entries; expected count is 1 (initial only).
    Compare: legacy behaviour pre-237b would observe ≥ 2 (initial + recursive).
  File 3 — `MerlinTests/Unit/IterationCapEscalationTests.swift`: when loop count reaches the
    near-ceiling threshold *and* no new tool calls or text were emitted in the last 3 turns,
    `handleEscalation(reason: .iterationCap)` is invoked. Verified by emitting
    `engine.escalation.start` and reading it back from the telemetry JSONL file via `readTelemetryEvents(fromFile:)`.
  File 4 — `MerlinTests/Unit/CleanStopOutcomeTests.swift`: when `EscalationHandler` returns
    `.stop`, the engine yields a `.cleanStop` event (or matching `.systemNote`) with the
    structured "Cannot continue / Suggested / Progress so far" template and *does not* re-enter
    `runLoop`.
  File 5 — `MerlinTests/Unit/RetryCounterDeletionTests.swift`: source-level check that
    `contextLengthRetryCount`, `maxContextOverrunRecoveryAttempts`, and the recursive
    `runLoop(userMessage:...)` self-call have been removed from `AgenticEngine.swift`.
    Implemented as a string-search test that loads the file and asserts the deleted symbols are
    absent. This is intentionally a regression guard.

---

## Edit

- `MerlinTests/Unit/EscalationHandlerTests.swift`
- `MerlinTests/Unit/RunLoopNoRecursionTests.swift`
- `MerlinTests/Unit/IterationCapEscalationTests.swift`
- `MerlinTests/Unit/CleanStopOutcomeTests.swift`
- `MerlinTests/Unit/RetryCounterDeletionTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `EscalationHandler`, `EscalationReason`,
`EscalationDecision`, and the missing `.cleanStop` AgentEvent case (or matching `.systemNote`
template). The `RetryCounterDeletionTests` expectation also fails because the legacy symbols
are still present.

## Commit

```bash
git add phases/phase-237a-executor-gate-tests.md \
    MerlinTests/Unit/EscalationHandlerTests.swift \
    MerlinTests/Unit/RunLoopNoRecursionTests.swift \
    MerlinTests/Unit/IterationCapEscalationTests.swift \
    MerlinTests/Unit/CleanStopOutcomeTests.swift \
    MerlinTests/Unit/RetryCounterDeletionTests.swift
git commit -m "Phase 237a — UnifiedExecutorGateTests (failing)"
```
