# Task 232a — Budget Telemetry Tests

> **Superseded by task 277.** The `TelemetryRecorder` / `TelemetrySink` / `TelemetryEmitter.sink` seam was removed. Telemetry tests now write to a temp JSONL file via `TelemetryEmitter.resetForTesting(path:)` / `flushForTesting()` and read it with `readTelemetryEvents(fromFile:)` (`TestHelpers/TelemetryTestSupport.swift`).

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 231b complete: release-blocker isolation, lifecycle, and config-watch fixes are in place.

This task opens the Budget-Aware Execution overhaul ( tasks 232–240). It is observability-only
— no behaviour change. It captures the data needed to calibrate every later task and to confirm
diagnoses for context-overrun and ReAct-stall failure modes.

New surface introduced in task 232b:
  - `TelemetryEmitter` enriches the existing `engine.turn.error` event with two new fields when
    the error is a `ProviderError.httpError`: `error_body` (first 500 chars of the response body,
    redacted of any `sk-` / `pk-` / `Bearer ` token-shaped substrings) and `error_status` (int).
  - New event `engine.preflight.estimate` emitted at the top of every `runLoop` turn with
    `estimated_tokens` (int), `provider_id` (string), and `slot` (string). Uses the existing
    `approximateTokens(in:)` helper at `AgenticEngine.swift`. No new estimator yet — that lands in 233b.
  - New event `planner.step.executing` emitted once per `PlanStep` immediately before the step's
    first LLM call, with `step_index` (int), `total_steps` (int), `complexity` (string),
    `description_prefix` (first 80 chars). Lets us see how the planner is actually decomposing.
  - `RedactedString.redacted(_ input: String) -> String` — pure helper in
    `Merlin/Engine/RedactedString.swift` that strips token-shaped substrings. Used for `error_body`.

TDD coverage:
  File 1 — `MerlinTests/Unit/RedactedStringTests.swift`: `redacted` strips `sk-…`, `pk-…`,
    `Bearer …` tokens and trims to 500 chars; leaves other text unchanged.
  File 2 — `MerlinTests/Unit/TelemetryErrorBodyTests.swift`: when `AgenticEngine` catches a
    `ProviderError.httpError(statusCode: 400, body: "context_length_exceeded …", providerID:)`,
    the next `engine.turn.error` event payload contains `error_body` (redacted, ≤500 chars) and
    `error_status: 400`. Uses a temp JSONL telemetry file helper in `TestHelpers/TelemetryTestSupport.swift`.
  File 3 — `MerlinTests/Unit/PreflightTelemetryTests.swift`: every `runLoop` turn emits exactly
    one `engine.preflight.estimate` event with `estimated_tokens > 0`, `provider_id` matching
    the resolved provider, and `slot` matching the working slot.
  File 4 — `MerlinTests/Unit/PlannerStepTelemetryTests.swift`: when the planner produces an
    N-step plan, exactly N `planner.step.executing` events are emitted in order with
    contiguous `step_index` from 0 through N-1 and matching `total_steps`.

---

## Edit

- `MerlinTests/Unit/RedactedStringTests.swift`
- `MerlinTests/Unit/TelemetryErrorBodyTests.swift`
- `MerlinTests/Unit/PreflightTelemetryTests.swift`
- `MerlinTests/Unit/PlannerStepTelemetryTests.swift`
- `TestHelpers/TelemetryTestSupport.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `RedactedString.redacted`, the missing
    the missing telemetry helper, and the absence of the new `error_body` / `engine.preflight.estimate` /
    `planner.step.executing` emit paths.

## Commit

```bash
git add tasks/task-232a-budget-telemetry-tests.md \
    MerlinTests/Unit/RedactedStringTests.swift \
    MerlinTests/Unit/TelemetryErrorBodyTests.swift \
    MerlinTests/Unit/PreflightTelemetryTests.swift \
    MerlinTests/Unit/PlannerStepTelemetryTests.swift \
    TestHelpers/TelemetryTestSupport.swift
git commit -m "Task 232a — BudgetTelemetryTests (failing)"
```
