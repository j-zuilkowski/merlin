# Task 395a - PCB DRC follow-on tests

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Plugin spec reference: plugins/electronics/spec.md#drc-and-pcb-follow-on
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

WHEN a schematic is verified THE electronics workflow SHALL extend to PCB verification through footprint evidence, board profile, placement, routing, DRC parsing, and bounded DRC repair.

## Red Tests

- Add tests for board profile schema.
- Add footprint assignment tests requiring pin compatibility proof.
- Add board outline, stackup, net-class, and placement constraint tests.
- Add DRC parser tests.
- Add bounded DRC repair-loop tests.
- Add `PCB_VERIFIED` status evidence tests.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/PCBDRCFollowOnTests
```

Expected red state: tests fail because PCB verification is not evidence-gated
through the new flow.

## Commit

Stage only PCB/DRC tests and fixtures.
