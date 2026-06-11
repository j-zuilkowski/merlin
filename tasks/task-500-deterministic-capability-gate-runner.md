# Task 500 - Deterministic Capability Gate Runner

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#evaluation-and-capability-scenarios
- Release ledger: docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md

## Behavior

WHEN release gate #8 runs THE workflow SHALL use
`scripts/release/run-capability-gate.sh`, not an ad hoc shell wrapper.

WHEN the runner starts THE workflow SHALL own all mutable release-gate state:
temporary Merlin config, temporary provider registry, `llama.cpp` on
`127.0.0.1:8081`, xcalibre on `127.0.0.1:8083`, focused S1/S2 xcodebuild
execution, logs, timeout, and cleanup.

WHEN the runner exits THE workflow SHALL restore the user's config/providers,
close ports `8081` and `8083`, and reap fixture helper apps such as
`TaskBoard.app`.

## Evidence

- Fail-first: `docs/e2e/2026-06-08-v2.4.0-release/logs/08-deterministic-runner.fail-first.log`
  records focused tests failing because
  `scripts/release/run-capability-gate.sh` did not exist.
- Green focused tests:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-deterministic-runner.focused.log`
  records `ReleaseCapabilityGateRunnerScriptTests` and
  `CapabilityConvergenceTests/testEvalShellTimeoutIsRepairableVerificationFailure`
  passing.
- Cheap runner checks passed:
  `bash -n scripts/release/run-capability-gate.sh`,
  `scripts/release/run-capability-gate.sh --self-test`, and
  `scripts/release/run-capability-gate.sh --dry-run`.
- Deterministic live gate attempt:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner.log`
  records the runner owning the release config, `llama.cpp` router, xcalibre,
  and focused S1/S2 test command. The run failed only on S1; S2 passed.
- Service logs:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner-llamacpp-router.log`,
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner-llamacpp-models.json`,
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner-xcalibre-build.log`,
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner-xcalibre-health.json`,
  and
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner-xcalibre-server.log`.
- Scenario artifacts:
  `merlin-eval/results/S1-harness-2026-06-11T13-04-11Z.md` records
  `tools 110 errors 1`, the
  `reloadFailed("llama.cpp router endpoint rejected models/load for llamacpp")`
  engine error, and red TaskBoard verification.
  `merlin-eval/results/S2-harness-2026-06-11T13-09-29Z.md` records
  `tools 15` and green Rust verification.
- Cleanup verification after the run found no listeners on `8081` or `8083`, no
  `run-capability-gate.sh`, no `llama-server`, no xcalibre backend, and no
  TaskBoard helper process. The user's `~/.merlin/config.toml` was restored to
  the pre-run slot values.

## Result

The deterministic runner is complete and covered by focused tests. Gate #8
remains failed because S1 still does not converge. The next task is not more
release-runner work; it is a targeted S1 repair for the
`llama.cpp` models/load rejection and incomplete TaskBoard fix loop.
