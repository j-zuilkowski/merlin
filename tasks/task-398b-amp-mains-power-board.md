# Task 398b - Amp mains power board implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#first-acceptance-target-25w-class-a-guitar-amplifier
- Plugin spec reference: plugins/electronics/spec.md#safety-policy
- Test task: tasks/task-398a-amp-mains-power-board-tests.md

## Behavior

The plugin SHALL support CAD and verification artifacts for the separate
amplifier power board while refusing to certify it safe to build or use.

## Implementation

- Add `amp_mains_power_supply` `DesignIntent` fixture.
- Add Circuit IR fixture for the power board.
- Add high-stakes safety policy enforcement.
- Add blocked certification language checks.
- Add explicit approval requirements for irreversible actions.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/AmpMainsPowerBoardTests
```

Expected green state: the power board fixture is represented under high-stakes
policy and Merlin never certifies build/use safety.

## Commit

Stage only power-board implementation, fixtures, and focused tests.
