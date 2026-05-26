# Task 367a — Electronics evidence store tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 367a is executed THE system SHALL add tests for artifact and gate evidence normalization.

GIVEN electronics artifacts and gate results are produced,
WHEN completion is evaluated,
THEN Merlin SHALL persist and report required evidence before returning complete.

## Red Test

- Assert missing artifacts block completion.
- Assert required artifacts/gates normalize into a final report.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsEvidenceStoreTests test
```

