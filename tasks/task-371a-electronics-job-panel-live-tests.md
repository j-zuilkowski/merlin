# Task 371a — Electronics job panel live workflow tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 371a is executed THE system SHALL add tests that the electronics job panel observes real workflow events.

GIVEN electronics workflows publish progress, artifacts, diagnostics, approvals, and reports,
WHEN the job store observes the bus,
THEN the panel model SHALL reflect those events for the active workspace.

## Red Test

- Assert report and health events are captured by `ElectronicsJobStore`.
- Assert blocked diagnostics remain visible.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsJobPanelLiveWorkflowTests test
```

