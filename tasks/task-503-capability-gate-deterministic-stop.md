# Task 503 - Capability Gate Deterministic Stop

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology
- Release ledger: `docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md`
- Prior repairs: `tasks/task-501-release-capability-model-preflight-repair.md`
- Prior repairs: `tasks/task-502-s1-verification-continuation-repair.md`
- Runner: `scripts/release/run-capability-gate.sh`
- Scenarios:
  `MerlinE2ETests/CapabilityScenarioTests.testS1SwiftGUIDebugCycle` and
  `MerlinE2ETests/CapabilityScenarioTests.testS2RustDebugCycle`

## Behavior

WHEN a release capability scenario reaches green verification output from a
verification tool, the E2E harness SHALL stop the scenario instead of allowing
additional narrative/tool turns to reopen a completed repair.

WHEN S1 performs a successful Swift source repair write, the E2E harness SHALL
stop that turn and let the test's deterministic verification command prove the
fixture state. This prevents S1 from wandering back into setup or unrelated GUI
exploration after the concrete TaskBoard source repair is made.

WHEN the release runner's focused xcodebuild exits before its timeout, the
runner SHALL kill the timeout watchdog process tree so a child `sleep` cannot
hold the `tee` pipe open after successful gate completion.

## Evidence

- Fail-first:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-verification-stop.fail-first.log`
  records the missing `CapabilityVerificationStopPolicy`.
- Fail-first:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-shell-path.fail-first.log`
  records the missing `ShellTool.defaultEnvironment` developer-tool PATH
  contract.
- Fail-first:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-runner-watchdog.fail-first.log`
  records the runner watchdog regression failing because the script used a plain
  `kill "$watchdog"` and could leave a child `sleep` alive.
- Focused green:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-task503.focused-green.log`
  records `CapabilityVerificationStopPolicyTests`,
  `CapabilityConvergenceTests`, `ShellToolEnvironmentTests`, and
  `ReleaseCapabilityGateRunnerScriptTests` passing 12 tests.
- Focused green:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-runner-watchdog.focused-green.log`
  records the watchdog regression passing.
- Syntax green:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-runner-watchdog.bash-n.log`
  records `bash -n scripts/release/run-capability-gate.sh` passing.
- Live gate evidence:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner.log`
  records S1 and S2 passing together under the deterministic gate runner.
- Scenario artifacts:
  `merlin-eval/results/S1-harness-2026-06-11T17-12-35Z.md` and
  `merlin-eval/results/S2-harness-2026-06-11T17-16-40Z.md`.
- Cleanup evidence:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner-cleanup.log`
  records no release runner, llama.cpp, xcalibre, xcodebuild, timeout watchdog,
  listeners on ports 8081/8083, or release provider markers after restoring the
  user's config/provider files from the runner backup.

## Result

Release gate #8 is passed with S1 and S2 green evidence. The runner hang found
after the green xcodebuild output is repaired by killing the watchdog process
tree, and cleanup evidence proves the release-owned services were closed. The
next fixed release item is gate #9: electronics/KiCad deterministic checks.
