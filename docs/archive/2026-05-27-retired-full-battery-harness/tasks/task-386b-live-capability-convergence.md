# Task 386b - Live capability convergence

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#full-green-e2e-battery-v24
- Test task: tasks/task-386a-live-capability-convergence-tests.md

## Behavior

WHEN an S1 or S2 live capability run receives failing verification output THE harness SHALL feed the exact failing command output back into the next repair iteration.
WHEN command evidence contradicts a model's environment diagnosis THE harness SHALL prefer command evidence and keep the scenario in repair mode.
WHEN the bounded repair policy is exhausted THE harness SHALL fail with the last command output, iteration count, provider/model IDs, and no-progress reason.

## Implementation

- Introduce a small convergence classifier for live capability runs that separates green verification, repairable test failure, missing prerequisite, provider/model unsupported, and no-progress exhaustion.
- Feed structured failure summaries from the last verification command back into the next agent prompt for S1 and S2.
- Detect repeated responses that do not produce file changes, tool calls, or improved verification output; escalate to the configured stronger local/remote slot when available.
- Make environment diagnostics evidence-based: a tool is considered missing only when the command runner captured a missing executable error before the model claim.
- Preserve bounded execution so live scenarios still terminate deterministically.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CapabilityConvergenceTests test
RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinE2ETests -destination 'platform=macOS' \
  -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS1SwiftGUIDebugCycle \
  -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS2RustDebugCycle test
```

Expected green state: convergence unit tests pass, S1 passes with `TaskBoardTests` green, and S2 passes with `cargo test` green when the configured providers support the required models.
