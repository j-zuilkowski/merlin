# Task 386a - Live capability convergence tests

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#full-green-e2e-battery-v24
- Prior failure: S1 timed out with TaskStoreTests still failing; S2 left the Rust overflow test failing and reported a false cargo environment diagnosis.

## Behavior

WHEN an S1 or S2 live capability run has failing verification output THE harness SHALL continue through a bounded fix-and-verify loop until the scenario command is green or the bounded no-progress policy is exhausted.
WHEN provider output claims a required tool is missing THE harness SHALL compare that claim with captured command execution evidence before treating it as an environment failure.
WHEN repeated agent output produces no file change and no verification progress THE harness SHALL escalate the recovery prompt or provider slot before consuming the remaining run budget.

## Red Tests

- Add unit coverage around capability-result classification so failing test output remains a repairable defect, not a pass, skip, or environment failure.
- Add a fixture for the S1 report where `TaskStoreTests.testDeleteRemovesTheTaskAtThatIndex()` and `TaskStoreTests.testSummaryCountsDoneOnly()` still fail; assert the harness schedules another repair iteration.
- Add a fixture for the S2 report where `cargo test` ran and `tests::total_does_not_overflow_on_a_large_ledger` overflowed; assert the harness rejects a later `cargo not found` explanation.
- Add no-progress/repetition coverage that proves repeated natural-language diagnosis without edits triggers escalation before the timeout.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CapabilityConvergenceTests test
```

Expected red state: the new convergence tests fail because the current harness can stop after diagnosis or repeated no-progress output while S1/S2 verification remains red.
