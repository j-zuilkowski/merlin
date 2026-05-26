# Task 368b — Electronics gate runner

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 368b is executed THE system SHALL implement deterministic electronics gate running.

GIVEN gate results are collected,
WHEN final status is computed,
THEN `COMPLETE` SHALL be legal only when all applicable gates pass or policy-permitted approvals are recorded.

## Implementation

- Add a gate runner over existing completion evaluator types.
- Emit diagnostics for missing/failing gates.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsGateRunnerTests test
```

