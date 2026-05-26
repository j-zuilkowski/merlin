# Task 373a — Electronics release gate tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 373a is executed THE system SHALL add tests for final electronics release gating.

GIVEN high-stakes or order-submission workflows,
WHEN approval records are missing,
THEN Merlin SHALL block release and order submission.

## Red Test

- Assert high-stakes signoff is mandatory.
- Assert vendor order submission requires explicit approval.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsReleaseGateTests test
```

