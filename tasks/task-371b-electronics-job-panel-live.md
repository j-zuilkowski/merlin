# Task 371b — Electronics job panel live workflow

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 371b is executed THE system SHALL wire electronics workflow events into the job panel model.

GIVEN workflow events occur,
WHEN the store receives them,
THEN backend health, progress, artifacts, diagnostics, approvals, and reports SHALL remain visible.

## Implementation

- Extend `ElectronicsJobStore` event parsing for final reports and backend health.
- Keep multiple sessions sharing the same workspace bus state.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsJobPanelLiveWorkflowTests test
```

