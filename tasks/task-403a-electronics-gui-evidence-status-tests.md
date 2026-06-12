# Task 403a - Electronics GUI Evidence Status Tests

Goal: add failing tests proving the electronics job panel can display
evidence-gated end-to-end workflow status.

Required assertions:

1. `ElectronicsJobStore` captures structured `ElectronicsEndToEndResult`
   progress events for a job.
2. The stored job exposes the real workflow status label such as `FAB_READY`,
   not a generic running or complete label.
3. Missing evidence from the harness result is retained for display.
4. The electronics job panel has an evidence-gate section.

Verify:

```bash
xcodegen generate && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testJobStoreCapturesEndToEndHarnessProgress \
  -only-testing:MerlinTests/ElectronicsJobPanelTests/testPanelTypeExistsWithOperationalSections
```

Expected before task 403b: fail because the job store ignores structured harness
progress payloads.
