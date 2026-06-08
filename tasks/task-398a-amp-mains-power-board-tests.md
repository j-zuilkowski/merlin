# Task 398a - Amp mains power board tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#first-acceptance-target-25w-class-a-guitar-amplifier
- Plugin spec reference: plugins/electronics/spec.md#safety-policy
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

The amplifier mains/power-supply board SHALL be a separate schematic and PCB
fixture under high-stakes safety policy.

## Red Tests

- Add `amp_mains_power_supply` fixture tests.
- Assert mains inlet, fuse, switch, PE bond, transformer primary, secondary
  interface, creepage/clearance constraints, and safety notes are represented.
- Assert high-stakes review state is required.
- Assert CAD verification does not imply safety certification.
- Assert build/use safety claims are blocked.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/AmpMainsPowerBoardTests
```

Expected red state: tests fail until the power board fixture and safety policy
are represented.

## Commit

Stage only mains board tests and fixtures.
