# Task 373b — Electronics release gate

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 373b is executed THE system SHALL enforce final electronics release gates.

GIVEN release or order submission lacks required approval,
WHEN the route runs,
THEN Merlin SHALL return blocked status and an approval diagnostic.

## Implementation

- Enforce high-stakes signoff and order submission approvals in production routes.
- Record approval evidence in final reports.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsReleaseGateTests test
```

