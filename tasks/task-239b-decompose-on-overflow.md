# Task 239b — Decompose-on-Overflow

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 239a complete: failing tests for decompose-first escalation with cross-provider fallback.

Closes the loop on "seamless regardless of provider/model/context." Decomposition is the default
response to overflow; cross-provider routing fires only when the planner declares the step atomic.

---

## Edit

- `Merlin/Providers/ProviderRegistry.swift` (or wherever the registry type lives — confirm
  during implementation) — add `providersOrderedByBudget()`. Skip providers whose `budget == nil`
  with the conservative default applied first (i.e. unconfigured providers still rank).
- `Merlin/Engine/EscalationHandler.swift`:
    - Extend `EscalationDecision` with `routeToProvider(providerID:reason:)`.
    - In `escalateOrStop`, on `.cannotDecompose`: look up
      `registry.providersOrderedByBudget()`, find the smallest-budget provider whose
      `usableInputTokens >= step.minContextRequired`, return
      `.routeToProvider(providerID: …, reason: planner reason)`. If no provider qualifies →
      `.stop(message: "step requires <X> tokens; no configured provider supports that budget")`.
- `Merlin/Engine/AgenticEngine.swift`:
    - `handleEscalation` learns `.routeToProvider`: temporarily override
      `slotAssignments[workingSlot]` for the duration of the current step, emit a `.systemNote`,
      re-enter the step's execution. Restore the prior assignment in a `defer`.
    - Per-step pre-flight: before each step in a planner-driven run, call `preflightCheck`
      against the step's projected size (use `TokenEstimator` on a synthesised request including
      the step's expected system prompt + RAG injection + the current context tail).

The architectural spec for decompose-first overflow handling lives in `spec.md` §
"V2.1 — Budget-Aware Execution" → "EscalationHandler — the single retry/escalation policy"
(already written). Implementation must match the documented ladder. Do not modify
`spec.md` in this task.

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

Expected: **BUILD SUCCEEDED** and all task 239a tests pass. All prior  tasks remain green.

## Commit

```bash
git add tasks/task-239b-decompose-on-overflow.md \
    Merlin/Providers/ProviderRegistry.swift \
    Merlin/Engine/EscalationHandler.swift \
    Merlin/Engine/AgenticEngine.swift
git commit -m "Task 239b — Decompose-on-overflow with cross-provider fallback"
```

## PASTE-LIST update

Append task 239a/239b under the "Budget-Aware Execution (v2.1.0)" section.

## Fixes

### Repetition-stall escalation (2026-05-19)

`recentProgressFlags` treats any turn with text or tool calls as progress, so a
model stuck in a verbatim loop — re-emitting the same prose intro ("I'll help you
build, test, and fix…") turn after turn while still issuing tool calls — never
trips the no-progress escalation. S1 failed this way: the execute model flailed
for the full 1800 s timeout without the escalation ladder ever firing.

- `EscalationReason.repetitionStall(repeats:lastObservation:)` — new case.
  `EscalationHandler.escalateOrStop` handles it as a capability failure (same as
  `criticExhausted`): route straight to the designated stronger provider, skip
  step refinement (refining is futile when the model keeps re-running the same
  turn). Stops cleanly when no stronger provider remains.
- `AgenticEngine.runLoop` fingerprints each tool-calling turn by its trimmed,
  lowercased 80-char prose prefix. When one non-empty prefix recurs ≥3× within a
  6-turn window, it escalates with `.repetitionStall`. Empty prefixes (tool-only
  turns) are ignored, so distinct un-narrated shell work is never misread as a
  loop. `prepareEscalationHandoff` clears the fingerprint window.
- Tests: `EscalationHandlerTests.testRepetitionStallRoutesToStrongerProvider`,
  `testRepetitionStallStopsWhenNoProviderAvailable`.
