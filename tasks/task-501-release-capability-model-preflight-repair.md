# Task 501 - Release Capability Model Preflight Repair

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology
- Release ledger: `docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md`
- Runner: `scripts/release/run-capability-gate.sh`
- Prior task: `tasks/task-500-deterministic-capability-gate-runner.md`

## Behavior

WHEN a local provider is addressed by its base provider ID and the selected
model is stored in `ProviderConfig.model`, the agent loop SHALL preflight local
model manager operations with the configured model ID, not the provider backend
ID.

WHEN the `llama.cpp` router catalog exposes a model but the router's
`/models/load` endpoint rejects mutation, `ensureModelLoaded(modelID:)` SHALL
accept the model if `/v1/models` proves the requested model is already exposed.

WHEN verbose Xcode verification fails after a long build log, the critic SHALL
preserve the named failing tests in the failure reason instead of truncating the
reason to early build noise.

## Evidence

- Fail-first focused tests:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-repair.fail-first.log`
  records the new critic and `llama.cpp` manager tests failing before the
  production repair.
- Focused green tests:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-repair.focused-green.log`
  records the critic and `llama.cpp` manager focused tests passing.
- Neighbor green tests:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-repair.neighbor-green.log`
  records `LlamaCppModelManagerTests`, `CriticEngineTests`, and
  `CapabilityConvergenceTests` passing 26 tests with 0 failures.
- Model-ID regression green test:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-repair.modelid-green.log`
  records `AgenticEngineContextAutoResizeTests` passing 3 tests with 0
  failures, including the `llamacpp` base-provider regression.
- Latest deterministic live runner evidence:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner.log`
  still records gate #8 as failed before this model-ID repair was applied: S1
  timed out and S2 hit
  `reloadFailed("llama.cpp router endpoint rejected models/load for llamacpp")`.
  The run cleaned up ports `8081` and `8083`.
- Latest S2 artifact:
  `merlin-eval/results/S2-harness-2026-06-11T14-13-11Z.md` records that S2 did
  not converge in that red run and left `add_rejects_non_numeric_amount` failing.

## Result

The code-level local model preflight repair is complete and covered by focused
tests. Release gate #8 is not complete: it must be rerun through
`scripts/release/run-capability-gate.sh` and pass both S1 and S2 before gate #9
or KiCad screenshot work can proceed.
