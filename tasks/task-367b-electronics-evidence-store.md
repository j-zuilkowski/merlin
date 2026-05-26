# Task 367b — Electronics evidence store

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 367b is executed THE system SHALL persist electronics completion evidence.

GIVEN required artifacts and gates are present,
WHEN final reporting runs,
THEN Merlin SHALL produce an auditable report from persisted evidence.

## Implementation

- Add evidence serialization helpers.
- Publish final report artifacts and diagnostics.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsEvidenceStoreTests test
```

