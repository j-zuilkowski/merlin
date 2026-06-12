# Task 393a - ERC parser and repair loop tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#erc-repair-loop
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

KiCad ERC output SHALL be parsed into structured violations, repaired only for
supported classes, and capped at three attempts before blocking.

## Red Tests

- Add ERC JSON parser tests.
- Add tests for supported repair classes: no-connect, power flag, net label
  mismatch, known endpoint connection, and proven pin mapping correction.
- Add tests proving unsupported ERC failures block.
- Add tests proving repair attempts stop after three iterations.
- Add tests for `SCHEMATIC_VERIFIED` evidence requirements.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ERCRepairLoopTests \
  -only-testing:MerlinTests/SchematicVerifiedStatusTests
```

Expected red state: tests fail because ERC parsing, repair actions, and
`SCHEMATIC_VERIFIED` status are missing.

## Commit

Stage only ERC repair-loop tests and fixtures.
