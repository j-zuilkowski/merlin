# Task 403b - Electronics GUI Evidence Status

Goal: make the electronics job panel show the same evidence-gated status emitted
by the backend harness.

Implementation requirements:

1. Add a structured job progress payload carrying `job_id`,
   `ElectronicsEndToEndResult`, and an optional message.
2. Publish that payload from structured runtime harness workflow calls.
3. Store the result on `ElectronicsJob`.
4. Display real harness status and missing evidence in the electronics job
   panel.
5. Do not map `FAB_READY`, `PCB_VERIFIED`, or `SCHEMATIC_VERIFIED` to false
   workflow completion.

Verify:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testJobStoreCapturesEndToEndHarnessProgress \
  -only-testing:MerlinTests/ElectronicsJobPanelTests/testPanelTypeExistsWithOperationalSections
```

Expected after task 403b: tests pass.
