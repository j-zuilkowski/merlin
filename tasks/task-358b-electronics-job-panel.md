# Task 358b — Electronics job panel

## Traceability

- spec.md — Electronics Product Completion Pass / UI completion surface

## Behavior

GIVEN electronics workflows run through the workspace bus,
WHEN a user needs to inspect or act on them,
THEN Merlin SHALL provide a focused electronics job/status panel for the active workspace.

## Implementation

- Add a workspace-scoped electronics job store fed by workspace bus events.
- Add an electronics job/status panel similar in weight to the file browser.
- Show backend health, active/finished jobs, progress, produced artifacts, blocked/failure diagnostics, approval requests, and final reports.
- Ensure sessions in the same workspace observe the same electronics job state.
- Keep the panel dense and operational; do not add a marketing-style or explanatory landing page.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests \
  -only-testing:MerlinTests/ElectronicsJobPanelTests test
```

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' build-for-testing
```

Manual UI validation: launch Merlin, open an electronics workspace, start or replay a fixture job, and verify the panel shows health, progress, artifacts, diagnostics, approvals, and final report state without overlap.

## Commit

```bash
git add Merlin MerlinTests plugins/electronics tasks
git commit -m "Task 358b — electronics job panel"
```
