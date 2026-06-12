# Task 446b - KiCad-Valid Schematic Geometry

Date: 2026-05-30

## Goal

Make generic Circuit IR schematic output truthful and KiCad-valid until a real
pin-placement and routing layer exists.

## Implementation Scope

1. Preserve Circuit IR net names in the schematic as KiCad-native Merlin-owned
   text metadata.
2. Do not emit KiCad electrical labels for nets that are not connected to
   placed symbol pins.
3. Do not emit wires or junctions without routed endpoints.
4. Parse and round-trip Merlin net and component metadata through the KiCad schematic
   parser/writer.
5. Keep the output visibly inspectable without claiming electrical connectivity
   that has not been synthesized.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests \
  -only-testing:MerlinTests/KiCadSchematicParserTests
```

Expected after Task 446b: generated schematic metadata round-trips and real
KiCad ERC reports no violations for the focused fixture when `kicad-cli` is
available.
