# Task 396a - Fabrication BOM release tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#status-model
- Roadmap reference: plugins/electronics/tasks.md#phase-9-fabrication-bom-and-release

## Behavior

Full electronics completion SHALL require schematic, PCB, ERC, DRC, BOM,
fabrication outputs, verification reports, and required approvals.

## Red Tests

- Add normalized BOM tests.
- Add MPN/vendor availability diagnostics tests.
- Add Gerber, drill, placement, and fabrication report evidence tests.
- Add fabricator profile validation tests.
- Add irreversible approval gate tests for order/fabrication submission.
- Add `FAB_READY` and final `COMPLETE` semantics tests.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests
```

Expected red state: tests fail until release completion is fully evidence-gated.

## Commit

Stage only fabrication/BOM/release tests and fixtures.
