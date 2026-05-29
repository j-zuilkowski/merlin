# Task 392b - Circuit IR to KiCad schematic implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#kicad-integration-strategy
- Test task: tasks/task-392a-circuit-ir-to-kicad-schematic-tests.md

## Behavior

The plugin SHALL compile valid Circuit IR into KiCad project and schematic files
with round-trip-safe structured mutation.

## Implementation

- Implement or complete `.kicad_sch` S-expression parser/writer.
- Add schematic builder APIs for symbols, fields, labels, wires, no-connects,
  and power symbols.
- Add source mapping from Circuit IR entries to KiCad refs/UUIDs.
- Add schematic parity checking.
- Remove any remaining product-specific schematic generation shortcuts.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests
```

Expected green state: valid Circuit IR produces schematic artifacts and parity
passes.

## Commit

Stage only schematic writer/materializer implementation and focused tests.
