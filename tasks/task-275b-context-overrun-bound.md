# Task 275b — Context-Overrun Retry Bound

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 275a complete: a failing test asserts that repeated context-overrun is bounded
and ends with a `.cleanStop`.

This task fixes the unbounded-retry regression. The infinite-loop bug class task 237
was meant to eliminate is not actually eliminated for the repeated-overrun path.

---

## Root cause

`EscalationHandler.escalateOrStop` (`Merlin/Engine/EscalationHandler.swift`) bounds work
with `successfulRefinements < maxRefinementsPerTurn`. But `successfulRefinements` is
incremented in only two places — the `.decomposed` outcome (line ~55) and the
registry-less `fallbackSteps` path (line ~67).

The `.cannotDecompose` branch **with** a registry returns `.routeToProvider` (line ~61)
**without incrementing the budget**. When a provider keeps failing with a context-length
`400`, the engine's catch block re-enters `handleEscalation` every iteration;
`escalateOrStop` keeps returning `.routeToProvider`; the budget guard never trips; the
turn loop spins until `maxLoopIterations` (~199 provider calls) and yields no terminal
`.cleanStop`.

---

## Edit — `Merlin/Engine/EscalationHandler.swift`

Make the per-turn budget count **every escalation attempt**, not only successful
decompositions. Required behaviour:

- Rename `successfulRefinements` → `escalationAttempts` (it no longer tracks only
  successes).
- Increment `escalationAttempts` once per `escalateOrStop` call that does real work —
  i.e. on **every** non-`.stop` decision it returns (`.continueWith` **and**
  `.routeToProvider`).
- The budget guard stays at the top: once `escalationAttempts >= maxRefinementsPerTurn`,
  return `.stop(message:)` ("refinement budget exhausted") without calling the planner
  again.
- A provider that has already been routed to and still fails must not be selected again.
  Track the set of provider IDs already returned via `.routeToProvider`; in the
  `.cannotDecompose` branch, exclude those when scanning `providersOrderedByBudget()`.
  When no un-tried provider qualifies, return `.stop`.

Net effect: repeated context-overrun consumes the budget in at most
`maxRefinementsPerTurn` escalation attempts, then returns `.stop`. `handleEscalation`
already yields `.cleanStop` on `.stop` and the engine breaks the turn loop — so the
provider is called a small finite number of times and the stream terminates cleanly.

Do **not** change `handleEscalation` in `AgenticEngine.swift`, the `.cleanStop` event,
or the first-overrun `else` branch (compact + `[CONTEXT_OVERRUN_RECOVERY]` directive) —
those are correct. The fix is entirely inside `EscalationHandler`.

If existing `EscalationHandlerTests` reference `successfulRefinements` by name or assert
the old "only successes count" semantics, update those assertions to the new
every-attempt-counts contract and list the changed test file in the commit.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and
`test_engine_bounds_retries_and_cleanStops_on_repeated_body_size_failures` passes.
`EscalationHandlerTests` and all other prior  tasks remain green (gated engine tests
still skip under a headless run).

## Commit

```bash
git add tasks/task-275b-context-overrun-bound.md \
    Merlin/Engine/EscalationHandler.swift \
    <updated EscalationHandlerTests file if changed>
git commit -m "Task 275b — Bound context-overrun escalation; fix ~199-retry loop"
```

## Fixes

`EscalationHandler.escalateOrStop` budget now counts every escalation attempt, closing
the `.routeToProvider` loophole that let repeated context-overrun retry unbounded
(~199 provider calls, no terminal event). Task 237's no-unbounded-retry invariant now
holds for the repeated-overrun path.
