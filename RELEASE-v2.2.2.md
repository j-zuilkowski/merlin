# Merlin v2.2.2 — Project Discipline: CI Readiness & Regression Fixes

Released: 2026-05-15

## Summary

v2.2.2 makes the v2.2 Project Discipline subsystem real and the test suite green on a
headless runner. It wires the discipline engine and pending-attention chip into the
running app, gates environment-dependent engine tests behind an opt-in so GitHub CI
passes, and fixes two genuine engine regressions found in code review. It also adds a
full external-dependency inventory.

## What's new

- The Project Discipline subsystem is now wired into the running app: `DisciplineEngine`
  is constructed in `AppState`, the pending-attention chip/panel appear in `ChatView`,
  the `SessionStart` hook surfaces findings, and a scan runs after each turn.
- Live-environment test gate: engine tests that need a real LLM endpoint are gated
  behind `RUN_LIVE_TESTS=1` (`skipUnlessLiveEnvironment()`), so CI and headless sandboxes
  run green; developers opt in for full coverage.
- `Requirements.md` — a complete external-dependency inventory (toolchain, providers,
  local runners, models, LoRA, KiCad, doc tools, services, MCP, frameworks) with a
  source link for every dependency.

## Internal changes

- Fixed the pending-attention chip showing stale data — the view model now reads through
  the shared `DisciplineEngine` instead of a separate queue instance.
- Fixed an unbounded context-overrun retry: `EscalationHandler` now consumes its
  per-turn budget on every escalation attempt, closing a loop that retried ~199 times
  without a terminal event.
- Fixed `parseSteps` silently dropping a planner step (and a downstream crash):
  `ComplexityTier` now decodes `high_stakes` / `highStakes` / `high-stakes` and falls
  back to `.standard` for unknown values.
- Removed the dead `TelemetryRecorder` / `TelemetrySink` / `TelemetryEmitter.sink` test
  seam; telemetry tests use the file-based `resetForTesting` / `flushForTesting` API via
  a shared `readTelemetryEvents(fromFile:)` helper.
- CI workflow: the build step now uses `set -o pipefail` so a failed build fails the job.

## Migration

- No user data migration required.
- The `v2.2.1` tag remains at the Phase 273b commit as an unreleased intermediate;
  v2.2.2 is the published successor to v2.2.0.
