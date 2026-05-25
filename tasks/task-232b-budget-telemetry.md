# Phase 232b — Budget Telemetry

> **Superseded by phase 277.** The `TelemetryRecorder` / `TelemetrySink` / `TelemetryEmitter.sink` seam was removed. Telemetry tests now write to a temp JSONL file via `TelemetryEmitter.resetForTesting(path:)` / `flushForTesting()` and read it with `readTelemetryEvents(fromFile:)` (`TestHelpers/TelemetryTestSupport.swift`).

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 232a complete: failing tests are in place for redacted error-body capture,
pre-flight estimate emit, and planner step trace.

Pure observability phase — no user-visible behaviour change. The new events feed the calibration
of every later phase in the 232–240 series. `engine.preflight.estimate` here uses the existing
rough estimator; phase 233b promotes that to the formal pre-flight gate.

---

## Edit

- `Merlin/Engine/RedactedString.swift` — new file. `enum RedactedString { static func redacted(_ input: String) -> String }`.
  Regex-strips `sk-[A-Za-z0-9_-]{8,}`, `pk-[A-Za-z0-9_-]{8,}`, `Bearer [A-Za-z0-9._-]+`, trims to 500 chars.
- `Merlin/Engine/AgenticEngine.swift` — at the catch block at line ~1083 (`catch { … "engine.turn.error" …}`),
  add `error_body` (via `RedactedString.redacted`) and `error_status` fields when the error is a
  `ProviderError.httpError`. The existing `error_domain` / `error_code` fields stay.
  Near the top of `runLoop` (after `workingSlot` is resolved, before the first provider call),
  emit `engine.preflight.estimate` using `approximateTokens(in: context)` and the resolved
  provider's id. In the planner-driven branch, emit `planner.step.executing` once per step
  before dispatching that step's first provider call.
- `TestHelpers/TelemetryTestSupport.swift` — shared helper for parsing telemetry JSONL in tests.

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

Expected: **BUILD SUCCEEDED** and all phase 232a tests pass. No prior tests regress.

## Commit

```bash
git add tasks/task-232b-budget-telemetry.md \
    Merlin/Engine/RedactedString.swift \
    Merlin/Engine/AgenticEngine.swift \
    Merlin/Engine/TelemetryEmitter.swift
git commit -m "Phase 232b — Budget telemetry (error body, pre-flight estimate, planner step trace)"
```

## PASTE-LIST update

Append the two new phases to `tasks/PASTE-LIST.md` under a new "Budget-Aware Execution (v2.1.0)" section.

## Fixes

- `Merlin/MCP/DomainRegistry.swift` now merges task types across all active domains instead of
  dropping the base software task type when non-software domains are active. This keeps the
  pre-existing `MultiDomainRegistryTests.test_taskTypesMergesAllActiveDomains()` expectation
  satisfied while preserving the domain activation order.
