# Task 502 - S1 Verification Continuation Repair

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology
- Release ledger: `docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md`
- Prior repairs: `tasks/task-501-release-capability-model-preflight-repair.md`
- Scenario: `MerlinE2ETests/CapabilityScenarioTests.testS1SwiftGUIDebugCycle`

## Behavior

WHEN a software-debug agent turn reaches the loop ceiling after a tool result
contains repairable failing verification output, the continuation SHALL carry
that verification evidence forward and instruct the next turn to fix the named
source defects.

WHEN the latest verification output names failing tests, the continuation SHALL
not fall back to a generic setup-oriented prompt such as running `git status` and
reviewing recent edits.

## Evidence

- Fail-first:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-taskboard-continuation.fail-first.log`
  records the new regression test failing because the loop-ceiling continuation
  discarded the `TaskStoreTests` failures and wrote the generic `run git status`
  instruction.
- Focused green:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-taskboard-continuation.focused-green.log`
  records `LoopContinuationTests/testLoopCeilingContinuationCarriesFailingVerificationTests`
  passing.
- Neighbor green:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/08-s1-taskboard-continuation.neighbor-green.log`
  records `LoopContinuationTests`, `CapabilityConvergenceTests`,
  `AgenticEngineContextAutoResizeTests`, and `LlamaCppModelManagerTests`
  passing 73 tests with 1 live-only skip and 0 failures.

## Result

Task #1 from the release blocker list is repaired at focused-test level:
Task 501 addressed the `llama.cpp` model preflight failure, and Task 502
addresses the S1 TaskBoard repair loop losing failing-test evidence across loop
ceiling continuations. The next release action is step #2: rerun gate #8 only
through `scripts/release/run-capability-gate.sh` and require S1 and S2 to pass
with evidence.
