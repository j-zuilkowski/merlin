# Task 393b - ERC parser and repair loop implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#erc-repair-loop
- Test task: tasks/task-393a-erc-parser-repair-loop-tests.md

## Behavior

The plugin SHALL use KiCad ERC as the schematic authority and derive
`SCHEMATIC_VERIFIED` only from approved intent, valid Circuit IR, schematic
artifacts, ERC report, and no blocking ERC errors.

## Implementation

- Run KiCad ERC through CLI.
- Parse ERC JSON into structured diagnostics.
- Implement repair patch schema and supported repair actions.
- Apply repairs through Circuit IR and KiCad parser/writer.
- Enforce a three-attempt cap.
- Add `SchematicVerificationReport` and `SCHEMATIC_VERIFIED`.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ERCRepairLoopTests \
  -only-testing:MerlinTests/SchematicVerifiedStatusTests
```

Expected green state: supported ERC issues repair, unsupported issues block, and
schematic verification is evidence-gated.

## Commit

Stage only ERC implementation, status code, reports, and focused tests.
