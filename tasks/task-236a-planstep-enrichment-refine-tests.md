# Task 236a — Enriched PlanStep + refineStep Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 235b complete: working-set caps and adaptive RAG keep request size under provider budget.

Enriches `PlanStep` with the metadata every later task wants to read, and introduces
`PlannerEngine.refineStep(...)` — the single decomposition entry point. Two future trigger
sites (ReAct iteration ceiling in 237b, budget overflow in 239b) both invoke this same helper,
so it must be designed for general use now.

New surface introduced in task 236b:
  - `enum CriticMode: String, Codable, Sendable { case required, optional, skip }` in
    `Merlin/Engine/CriticMode.swift`.
  - `enum StepCriterion: Sendable, Equatable` in `Merlin/Engine/StepCriterion.swift`:
    ```swift
    enum StepCriterion: Sendable, Equatable, Codable {
        case prose(String)                       // legacy free-form criterion
        case buildSucceeds
        case testsPass(scheme: String?)
        case fileExists(path: String)
        case regexMatch(pattern: String, in: RegexTarget)
        case shellExitZero(command: String)
        enum RegexTarget: String, Codable, Sendable { case stdout, file }
    }
    ```
  - Enriched `PlanStep`:
    ```swift
    struct PlanStep: Sendable {
        var description: String
        var successCriteria: [StepCriterion]   // was a single String
        var complexity: ComplexityTier
        var parallelSafe: Bool = false
        var tokenBudget: Int                   // expected total request size for this step
        var requiresCritic: CriticMode = .optional
        var minContextRequired: Int            // floor on usableInputTokens needed to run this step
    }
    ```
    Backwards-compat: a legacy decode where `successCriteria` is a single string wraps it in
    `[.prose(s)]`. `tokenBudget` defaults to the active provider's `usableInputTokens / 4`
    when absent. `minContextRequired` defaults to `tokenBudget * 2`.
  - `enum RefineReason: Sendable { case iterationCap(loopCount: Int, lastObservation: String); case budget(estimated: Int, budget: Int); case explicit(String) }`.
  - `enum RefineOutcome: Sendable { case decomposed([PlanStep]); case cannotDecompose(reason: String) }`.
  - `PlannerEngine.refineStep(_ step: PlanStep, reason: RefineReason, context: [Message]) async -> RefineOutcome`.
    Calls the orchestrate-slot provider with a prompt that includes the original step, the
    failure reason, and the active provider's budget. Returns a list of substeps with
    `tokenBudget` strictly smaller than the parent's, or `.cannotDecompose` when the step is
    atomic (one indivisible artifact, single huge input, etc.). Emits
    `planner.refine.start` / `planner.refine.success` / `planner.refine.cannot_decompose`.

TDD coverage:
  File 1 — `MerlinTests/Unit/StepCriterionTests.swift`: round-trip Codable for each case;
    legacy decode of `"successCriteria": "build the thing"` → `[.prose("build the thing")]`.
  File 2 — `MerlinTests/Unit/EnrichedPlanStepTests.swift`: defaults for `tokenBudget`,
    `minContextRequired`, `requiresCritic` when absent in decoded JSON; serialization keeps new
    fields when present.
  File 3 — `MerlinTests/Unit/PlannerRefineStepTests.swift`: against a mocked orchestrate provider:
    a `.budget` reason with a 50 000-token step and a 32 000-token budget returns at least 2
    substeps each with `tokenBudget < parent.tokenBudget`. A `.iterationCap` reason returns
    substeps with smaller `description` scope. An atomic input ("here is one 180k-token file")
    returns `.cannotDecompose(reason: …)`.
  File 4 — `MerlinTests/Unit/PlannerRefineTelemetryTests.swift`: each `refineStep` call emits
    exactly one terminal telemetry event (`success` or `cannot_decompose`) with payload fields.

---

## Edit

- `MerlinTests/Unit/StepCriterionTests.swift`
- `MerlinTests/Unit/EnrichedPlanStepTests.swift`
- `MerlinTests/Unit/PlannerRefineStepTests.swift`
- `MerlinTests/Unit/PlannerRefineTelemetryTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `CriticMode`, `StepCriterion`, the new
`PlanStep` fields, `RefineReason`, `RefineOutcome`, and `PlannerEngine.refineStep`.

## Commit

```bash
git add tasks/task-236a-planstep-enrichment-refine-tests.md \
    MerlinTests/Unit/StepCriterionTests.swift \
    MerlinTests/Unit/EnrichedPlanStepTests.swift \
    MerlinTests/Unit/PlannerRefineStepTests.swift \
    MerlinTests/Unit/PlannerRefineTelemetryTests.swift
git commit -m "Task 236a — EnrichedPlanStepAndRefineTests (failing)"
```
