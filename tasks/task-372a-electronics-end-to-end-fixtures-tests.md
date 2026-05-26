# Task 372a — Electronics end-to-end fixture tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 372a is executed THE system SHALL add end-to-end electronics fixture tests.

GIVEN fixture evidence is complete,
WHEN electronics workflow routes run through the bus,
THEN they SHALL return a final report and never bypass required artifacts or gates.

## Red Test

- Use local fixture evidence for a complete workflow.
- Assert all incomplete fixtures block.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsEndToEndFixtureTests test
```

