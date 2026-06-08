# Task 390a - DesignIntent approval flow tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#designintent
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

WHEN requirements are natural-language-originated THE plugin SHALL draft a
`DesignIntent` and require user approval before KiCad mutation or schematic
verification.

## Red Tests

- Add tests for drafting `DesignIntent` from requirements without creating KiCad
  files.
- Add tests proving unapproved natural-language-originated intent blocks compile
  or schematic materialization.
- Add tests proving approved intent can proceed to the next tool boundary.
- Add tests for rejected intent blocking with diagnostics.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests
```

Expected red state: tests fail because approval state is not enforced.

## Commit

Stage only approval-flow tests and fixtures.
