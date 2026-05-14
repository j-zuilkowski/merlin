# Phase 239a — Decompose-on-Overflow Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 238b complete: critic gating active. Pre-flight overflow currently routes through
`EscalationHandler` (237b) which already calls `planner.refineStep(reason: .preflightOverflow)`.

This phase tightens that path into the documented ladder and adds cross-provider escalation as
the *last-resort* fallback (the inverted priority order: decompose first, escalate to a bigger
model only when the work is atomic).

Behaviour after this phase:
  1. Pre-flight overflow detected.
  2. Working-set caps re-applied + summary compaction (already done in 234b).
  3. If still over → `EscalationHandler.escalateOrStop(reason: .preflightOverflow)` →
     `planner.refineStep(reason: .budget)`.
  4. `.decomposed([substeps])` → executor runs substeps one by one, each pre-flighted independently.
  5. `.cannotDecompose(reason)` → **cross-provider escalation**: try the next-largest-budget
     slot whose `usableInputTokens >= step.minContextRequired`.
  6. If no larger slot configured or available → graceful `.cleanStop` (no recursion, no retry).

New surface introduced in phase 239b:
  - `ProviderRegistry.providersOrderedByBudget() -> [(id: String, budget: ProviderBudget)]` —
    return all configured providers sorted by `usableInputTokens` descending. (Method name
    flexible — match local conventions on whatever type backs the registry.)
  - `EscalationHandler.escalateOrStop` extension: when planner returns `.cannotDecompose`, call
    `ProviderRegistry.providersOrderedByBudget()` and pick the smallest-budget provider that
    still satisfies `step.minContextRequired`. If none → `.stop`.
  - `EscalationDecision` gains a case:
    ```swift
    enum EscalationDecision: Sendable {
        case continueWith(replacementSteps: [PlanStep])
        case routeToProvider(providerID: String, reason: String)
        case stop(message: String)
    }
    ```
  - `AgenticEngine.handleEscalation(...)` learns `.routeToProvider` — re-runs the current step
    with `slotAssignments[currentSlot] = providerID` temporarily overridden for the duration of
    the step, then restored. Emits `engine.escalation.route_to_provider` telemetry.
  - Per-step pre-flight inside the planner-driven execution path: before each `PlanStep`
    starts, `preflightCheck` is called against the projected request size for that step. If
    over → escalation, before any provider call has been made.
  - User-visible: a `.systemNote` "Step too large for current model; switching to <providerID>"
    when cross-provider routing fires.

TDD coverage:
  File 1 — `MerlinTests/Unit/EscalationDecomposeFirstTests.swift`: pre-flight overflow with a
    decomposable step → escalation returns `.continueWith([substep1, substep2])`. Neither
    `routeToProvider` nor `stop` are produced. The two substeps execute sequentially with
    independent pre-flight.
  File 2 — `MerlinTests/Unit/EscalationAtomicOverflowTests.swift`: pre-flight overflow with an
    atomic step (planner returns `.cannotDecompose`) → escalation returns
    `.routeToProvider(providerID:)` matching the smallest-budget provider that fits. With no
    matching provider → `.stop`.
  File 3 — `MerlinTests/Unit/ProviderRegistryOrderingTests.swift`: providers sorted strictly
    descending by `usableInputTokens`; ties broken by id; unconfigured providers excluded.
  File 4 — `MerlinTests/Unit/PerStepPreflightTests.swift`: in a 3-step plan, step 2 would
    overflow at full size; per-step pre-flight fires before step 2's first provider call;
    escalation triggers without an unnecessary 400 round-trip.
  File 5 — `MerlinTests/Unit/CrossProviderRouteSystemNoteTests.swift`: when escalation returns
    `.routeToProvider`, the engine yields a `.systemNote` containing
    "switching to <providerID>" and the step then completes against the new provider.

---

## Edit

- `MerlinTests/Unit/EscalationDecomposeFirstTests.swift`
- `MerlinTests/Unit/EscalationAtomicOverflowTests.swift`
- `MerlinTests/Unit/ProviderRegistryOrderingTests.swift`
- `MerlinTests/Unit/PerStepPreflightTests.swift`
- `MerlinTests/Unit/CrossProviderRouteSystemNoteTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming the new `EscalationDecision.routeToProvider` case,
the `ProviderRegistry.providersOrderedByBudget` method, and the missing per-step pre-flight call.

## Commit

```bash
git add phases/phase-239a-decompose-on-overflow-tests.md \
    MerlinTests/Unit/EscalationDecomposeFirstTests.swift \
    MerlinTests/Unit/EscalationAtomicOverflowTests.swift \
    MerlinTests/Unit/ProviderRegistryOrderingTests.swift \
    MerlinTests/Unit/PerStepPreflightTests.swift \
    MerlinTests/Unit/CrossProviderRouteSystemNoteTests.swift
git commit -m "Phase 239a — DecomposeOnOverflowTests (failing)"
```
