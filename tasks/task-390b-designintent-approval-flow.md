# Task 390b - DesignIntent approval flow implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#designintent
- Test task: tasks/task-390a-designintent-approval-flow-tests.md

## Behavior

The plugin SHALL allow Merlin to assist intent drafting while preventing KiCad
mutation until the user approves natural-language-originated intent.

## Implementation

- Add a design-intent drafting capability or complete `kicad_build_intent_model`.
- Extract unresolved decisions into the draft.
- Add an approval action and persisted approval state.
- Block KiCad mutation when approval is missing.
- Optionally add draft-only preview mode that cannot complete gates.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests
```

Expected green state: requirements produce draft intent, approved intent can
proceed, and unapproved intent cannot create verified artifacts.

## Commit

Stage only approval-flow implementation and focused tests.
