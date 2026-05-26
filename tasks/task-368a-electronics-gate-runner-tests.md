# Task 368a — Electronics gate runner tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 368a is executed THE system SHALL add tests for deterministic electronics completion gates.

GIVEN a workflow reaches verification,
WHEN required gate results are missing or failing,
THEN the workflow SHALL block and name the failed gates.

## Red Test

- Cover connectivity, ERC, DRC, parity, fabrication, simulation, visual QA, and high-stakes signoff gate behavior.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsGateRunnerTests test
```

