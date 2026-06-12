# Task 396b - Fabrication BOM release implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#status-model
- Test task: tasks/task-396a-fab-bom-release-tests.md

## Behavior

The plugin SHALL distinguish `FAB_READY` and final `COMPLETE` from schematic or
PCB verification and SHALL require explicit approvals for irreversible actions.

## Implementation

- Add normalized BOM schema and checks.
- Add vendor availability and MPN diagnostics.
- Export Gerbers, drills, BOM, placement files, and fabrication reports.
- Validate fabricator profiles.
- Generate release packages.
- Gate irreversible actions on explicit approval.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests
```

Expected green state: fabrication readiness and final completion require all
artifact and approval evidence.

## Commit

Stage only fabrication/BOM/release implementation and focused tests.
