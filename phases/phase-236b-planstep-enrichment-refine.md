# Phase 236b — Enriched PlanStep + refineStep

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 236a complete: failing tests for enriched `PlanStep`, `StepCriterion`, `refineStep`, and
its telemetry.

After this phase the planner emits richer plans (with structured criteria, token budgets, and
critic policy per step) and exposes a single decomposition entry point usable from both the
budget-overflow and ReAct-stall trigger sites in later phases.

---

## Edit

- `Merlin/Engine/CriticMode.swift` — new file.
- `Merlin/Engine/StepCriterion.swift` — new file.
- `Merlin/Engine/PlannerEngine.swift`:
    - Enrich `PlanStep` per the 236a spec. Provide `Codable` conformance with the legacy-string
      compatibility decoder. Keep `successCriteria` accessible both as `[StepCriterion]` and via
      `var proseSummary: String { … }` for log/UI consumers.
    - Update the existing `decompose(task:context:)` prompt to request the new fields. Include
      the active provider's `ProviderBudget.usableInputTokens` so the planner sizes
      `tokenBudget` and `minContextRequired` realistically.
    - Add `refineStep(_:reason:context:) async -> RefineOutcome`. Prompt includes:
      original step description, current `tokenBudget`, the `RefineReason`, instruction to
      produce substeps with strictly smaller budgets *or* explicitly declare
      `.cannotDecompose(reason:)`.
- `Merlin/Engine/AgenticEngine.swift`:
    - Wherever a freshly-decomposed plan is consumed today, accept the enriched shape. No
      executor-side behaviour change yet — that lands in 237b. Fields are read but not yet
      enforced.

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

Expected: **BUILD SUCCEEDED** and all phase 236a tests pass.

## Commit

```bash
git add phases/phase-236b-planstep-enrichment-refine.md \
    Merlin/Engine/CriticMode.swift \
    Merlin/Engine/StepCriterion.swift \
    Merlin/Engine/PlannerEngine.swift \
    Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 236b — Enriched PlanStep and PlannerEngine.refineStep"
```

## PASTE-LIST update

Append phase 236a/236b under the "Budget-Aware Execution (v2.1.0)" section.
