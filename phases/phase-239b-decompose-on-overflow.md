# Phase 239b — Decompose-on-Overflow

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 239a complete: failing tests for decompose-first escalation with cross-provider fallback.

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

The architectural spec for decompose-first overflow handling lives in `architecture.md` §
"V2.1 — Budget-Aware Execution" → "EscalationHandler — the single retry/escalation policy"
(already written). Implementation must match the documented ladder. Do not modify
`architecture.md` in this phase.

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

Expected: **BUILD SUCCEEDED** and all phase 239a tests pass. All prior phases remain green.

## Commit

```bash
git add phases/phase-239b-decompose-on-overflow.md \
    Merlin/Providers/ProviderRegistry.swift \
    Merlin/Engine/EscalationHandler.swift \
    Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 239b — Decompose-on-overflow with cross-provider fallback"
```

## PASTE-LIST update

Append phase 239a/239b under the "Budget-Aware Execution (v2.1.0)" section.
