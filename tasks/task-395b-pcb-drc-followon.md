# Task 395b - PCB DRC follow-on implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#drc-and-pcb-follow-on
- Test task: tasks/task-395a-pcb-drc-followon-tests.md

## Behavior

The plugin SHALL turn a verified schematic into a PCB candidate and derive
`PCB_VERIFIED` from KiCad DRC evidence.

## Implementation

- Add board profile, outline, stackup, and net-class schemas.
- Assign footprints from resolver evidence.
- Add placement and routing integration through DSN/SES and FreeRouting.
- Run and parse KiCad DRC.
- Add bounded DRC repair actions.
- Define `PCB_VERIFIED` distinct from fabrication completion.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/PCBDRCFollowOnTests
```

Expected green state: DRC failures are parsed and repaired or blocked, and
`PCB_VERIFIED` is evidence-gated.

## Commit

Stage only PCB/DRC implementation and focused tests.
