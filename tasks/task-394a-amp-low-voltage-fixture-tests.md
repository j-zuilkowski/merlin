# Task 394a - Amp low-voltage fixture tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#first-acceptance-target-25w-class-a-guitar-amplifier
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

The 25W Class A amplifier SHALL be represented as generic `DesignIntent` and
Circuit IR fixture data, not a hard-coded generator.

## Red Tests

- Add fixture tests for `amp_low_voltage_audio` design intent and Circuit IR.
- Assert the fixture includes preamp, 3-band tone, sweepable boost/cut filter,
  driver, output stage, speaker output, low-voltage rail distribution, and
  thermal constraints.
- Assert unresolved decisions are explicit.
- Assert the fixture passes through generic resolver/materializer/ERC paths.
- Assert no named amp generator code path is used.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/AmpLowVoltageFixtureTests
```

Expected red state: tests fail until the amp fixture exists as generic design
data.

## Commit

Stage only amp fixture tests and fixture data needed for red tests.
