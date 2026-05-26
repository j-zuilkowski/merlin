# Task 358a — Electronics job panel tests

## Traceability

- spec.md — Electronics Product Completion Pass / UI completion surface

## Behavior

GIVEN electronics jobs publish workspace bus events,
WHEN the user opens the electronics job/status panel,
THEN the panel SHALL show job state, backend health, progress, artifacts, diagnostics, approvals, and final reports for the active workspace.

## Red Test

Add failing tests that prove:

- a workspace-scoped electronics job store subscribes to bus events;
- multiple sessions in the same workspace see the same electronics job state;
- the panel exposes rows/sections for backend health, active jobs, progress, artifacts, diagnostics, approvals, and reports;
- blocked and failed jobs show actionable diagnostics;
- approval requests are visible and auditable from the panel.

Suggested files:

- `MerlinTests/Unit/ElectronicsJobStoreTests.swift`
- `MerlinTests/Unit/ElectronicsJobPanelTests.swift`

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests \
  -only-testing:MerlinTests/ElectronicsJobPanelTests test
```

Expected: tests fail until the job store and panel exist.

## Commit

```bash
git add MerlinTests/Unit/ElectronicsJobStoreTests.swift \
        MerlinTests/Unit/ElectronicsJobPanelTests.swift \
        tasks/task-358a-electronics-job-panel-tests.md
git commit -m "Task 358a — electronics job panel tests"
```
