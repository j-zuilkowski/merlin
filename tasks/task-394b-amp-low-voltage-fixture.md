# Task 394b - Amp low-voltage fixture implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#first-acceptance-target-25w-class-a-guitar-amplifier
- Test task: tasks/task-394a-amp-low-voltage-fixture-tests.md

## Behavior

The generic electronics pipeline SHALL process the low-voltage amplifier fixture
to `SCHEMATIC_VERIFIED` or block with specific unresolved design decisions.

## Implementation

- Add `amp_low_voltage_audio` `DesignIntent` fixture.
- Add Circuit IR fixture for the low-voltage audio board.
- Add a separate `amp_mains_power_supply` fixture stub for the second board.
- Run the low-voltage fixture through resolver, schematic materializer, ERC, and
  schematic verification.
- Keep every path generic and data-driven.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/AmpLowVoltageFixtureTests
```

Expected green state: fixture flow is generic and reaches schematic verification
or a specific honest block.

## Commit

Stage only fixture implementation, fixture data, and focused tests.
