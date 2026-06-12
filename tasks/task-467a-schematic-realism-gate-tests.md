# Task 467a - Schematic Realism Gate Tests

## Goal

Prevent schematic workflow advancement from placeholder or composite KiCad
schematics that do not represent the Circuit IR as real discrete components.

## Requirements

1. A schematic realism validator must reject metadata-only components and
   composite block symbols.
2. The validator must require current KiCad schematic format and the
   `merlin-electronics` generator.
3. Every Circuit IR component must appear as an emitted KiCad symbol with
   matching refdes, selected symbol, footprint, source, and pins.
4. Every Circuit IR net must appear as emitted connectivity labels, not only
   metadata text.
5. The structured end-to-end harness must block before
   `SCHEMATIC_VERIFIED` when Circuit IR is a composite caricature rather than a
   discrete schematic.

## Fail-First Command

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testSchematicRealismValidatorPassesMaterializedDiscreteCircuitIR \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testSchematicRealismValidatorRejectsCompositeMetadataOnlyCaricature \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testCompositeCircuitIRSchematicCannotReachSchematicVerified
```

## Expected Red State

Build or tests fail before implementation because the schematic realism
validator and harness wiring do not exist yet.
