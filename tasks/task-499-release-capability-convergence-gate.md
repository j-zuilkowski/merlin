# Task 499 - Release Capability Convergence Gate

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#evaluation-and-capability-scenarios

## Behavior

WHEN the v2.4.0 release ledger reaches the capability convergence gate THE
workflow SHALL run the focused live S1 and S2 capability scenarios from
`CapabilityScenarioTests`.

WHEN S1 or S2 fails, times out, skips, or leaves the verification classifier
non-green THE gate SHALL preserve the xcodebuild log and keep post-green
screenshots blocked.

WHEN both scenarios pass THE workflow SHALL record the xcode result and generated
scenario evidence before advancing.

## Goal

Run release gate #8 without running the full AmpDemo GUI demo or later screenshot
gates.

## Evidence

- Fail-first: `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-scenarios.fail-first.log`
  recorded S1/S2 failing because the configured live local provider at
  `127.0.0.1:8081` was not running after the separate gate #6 router smoke had
  cleaned it up. The S2 fixture verification stayed red after the provider
  errors, so gate #8 must own a router process during the convergence run.
- Second red: `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-scenarios.model-mismatch.log`
  recorded the gate-owned router running but the user config still pointing
  live slots at `llamacpp:qwen3-coder-next-local`, which the release router
  preset does not expose. Gate #8 must use an isolated release config that
  matches its release router preset and restores the user's config afterward.
- Third red: `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-scenarios.log`
  recorded an isolated release config plus gate-owned router, then stalled in
  the S1 workflow after the app probed `localhost:8083` without a gate-owned
  xcalibre service. The wrapper was interrupted and restored the user's config;
  port `8081` was confirmed closed afterward.
- Scenario artifacts:
  `merlin-eval/results/S1-harness-2026-06-08T19-31-05Z.md`,
  `merlin-eval/results/S2-harness-2026-06-08T19-31-10Z.md`,
  `merlin-eval/results/S1-harness-2026-06-08T19-32-30Z.md`, and
  `merlin-eval/results/S2-harness-2026-06-08T19-32-32Z.md` show S1/S2
  non-convergence in the completed attempts: no tool calls were captured and
  the fixture verification tests stayed red.

## Result

Gate #8 is failed, not running. The next task must add a deterministic release
gate runner before any further live S1/S2 attempt. The runner must own
`llama.cpp` on `127.0.0.1:8081`, xcalibre on `127.0.0.1:8083`, release
config/provider registry isolation, strict wall-clock timeouts, log capture,
artifact capture, and cleanup.
