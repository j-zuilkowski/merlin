# Task 233a — ProviderBudget + Pre-Flight Gate Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 232b complete: telemetry emits error body, pre-flight estimate, and per-step planner trace.

Introduces the contract every later task depends on: each provider/model entry advertises an
input-token budget, and the engine refuses to send a request that would exceed it. Reactive
400-on-overrun handling stays in place for safety, but stops being load-bearing — most overruns
disappear because pre-flight blocks them.

New surface introduced in task 233b:
  - `ProviderBudget` value type in `Merlin/Providers/ProviderBudget.swift`:
    `struct ProviderBudget: Sendable { let maxInputTokens: Int; let reservedOutputTokens: Int;
    var usableInputTokens: Int { maxInputTokens - reservedOutputTokens } }`.
  - `ProviderConfig.budget: ProviderBudget?` field (in whichever struct backs `registry?.config(for:)`
    today — confirm the type while implementing). Optional so legacy configs without a budget keep working;
    a missing budget routes through a conservative default of `(maxInputTokens: 32_000, reservedOutputTokens: 4_096)`.
  - `TokenEstimator.estimate(request: CompletionRequest) -> Int` — pure function in
    `Merlin/Engine/TokenEstimator.swift`. Encodes the request body via the existing
    `encodeRequest(_:baseURL:model:)` path, returns `bytes/4 * 1.2 + 512` rounded up. Used at the
    pre-flight gate and from `compactWithSummaryIfNeeded` if/when it inspects request size.
  - `AgenticEngine.preflightCheck(request:provider:) async throws -> PreflightOutcome` where
    `enum PreflightOutcome { case ok; case wouldOverflow(estimated: Int, budget: Int) }`.
    Called immediately before `completeWithRetry`. `.wouldOverflow` triggers compaction (existing
    `compactWithSummaryIfNeeded`); if still over, rethrows `EngineError.preflightOverflow` —
    later  tasks (237b, 239b) handle that error.
  - Lowered thresholds in `Merlin/Engine/ContextManager.swift`:
    `preRunCompactionThreshold = 6_000` (was 10_000) and `midLoopCompactionThreshold = 20_000`
    (was 40_000). Both still tunable via `var` for tests.
  - New telemetry events: `engine.preflight.ok`, `engine.preflight.overflow`,
    `engine.preflight.compacted` (post-compaction outcome).

TDD coverage:
  File 1 — `MerlinTests/Unit/ProviderBudgetTests.swift`: `ProviderBudget.usableInputTokens` math,
    default-budget fallback when `config.budget == nil`.
  File 2 — `MerlinTests/Unit/TokenEstimatorTests.swift`: estimator monotonic in message size,
    estimate ≥ raw bytes / 4 (i.e. the 1.2x headroom is applied), never returns < 512.
  File 3 — `MerlinTests/Unit/PreflightGateTests.swift`: when `estimate > budget.usableInputTokens`,
    pre-flight first compacts (existing summary-compaction path) and re-estimates; if still over,
    throws `EngineError.preflightOverflow` and emits `engine.preflight.overflow`.
  File 4 — `MerlinTests/Unit/CompactionThresholdTests.swift`: `preRunCompactionThreshold == 6000`,
    `midLoopCompactionThreshold == 20000`; pre-run compaction fires at 6 001 tokens.
  File 5 — `MerlinTests/Unit/PreflightOkTelemetryTests.swift`: a request well below budget emits
    `engine.preflight.ok` (no compaction, no overflow event).

---

## Edit

- `MerlinTests/Unit/ProviderBudgetTests.swift`
- `MerlinTests/Unit/TokenEstimatorTests.swift`
- `MerlinTests/Unit/PreflightGateTests.swift`
- `MerlinTests/Unit/CompactionThresholdTests.swift`
- `MerlinTests/Unit/PreflightOkTelemetryTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `ProviderBudget`, `TokenEstimator`,
`AgenticEngine.preflightCheck`, `EngineError.preflightOverflow`, and the lowered threshold constants.

## Commit

```bash
git add tasks/task-233a-provider-budget-preflight-tests.md \
    MerlinTests/Unit/ProviderBudgetTests.swift \
    MerlinTests/Unit/TokenEstimatorTests.swift \
    MerlinTests/Unit/PreflightGateTests.swift \
    MerlinTests/Unit/CompactionThresholdTests.swift \
    MerlinTests/Unit/PreflightOkTelemetryTests.swift
git commit -m "Task 233a — ProviderBudgetAndPreflightTests (failing)"
```
