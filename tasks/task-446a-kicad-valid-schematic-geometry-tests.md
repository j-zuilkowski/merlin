# Task 446a - KiCad-Valid Schematic Geometry Tests

Date: 2026-05-30

## Goal

Add focused tests proving Circuit IR schematic materialization does not create
KiCad ERC violations from disconnected labels, wires, or off-grid endpoints.

## Test Scope

1. Materialized Circuit IR net names remain available as Merlin metadata.
2. Circuit IR net metadata does not emit KiCad electrical labels unless real
   symbol pins and routed endpoints exist.
3. Materialized Circuit IR does not emit disconnected schematic wires.
4. The materialized schematic passes real KiCad ERC when `kicad-cli` is
   available.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests
```

Expected before Task 446b: materialized Circuit IR can create dangling label,
wire, or off-grid ERC violations.
