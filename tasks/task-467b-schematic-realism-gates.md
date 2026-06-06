# Task 467b - Schematic Realism Gates

## Implementation

Added `SchematicRealismValidator` for Circuit IR to KiCad schematic evidence.
The validator blocks schematic advancement when the parsed schematic:

- uses stale KiCad schematic format;
- uses a generator other than `merlin-electronics`;
- contains metadata-only or composite block symbols;
- omits emitted KiCad symbols for Circuit IR components;
- loses selected symbol, footprint, source, source-evidence, or pin evidence;
- omits emitted KiCad connectivity labels for Circuit IR nets.

`ElectronicsEndToEndHarness` now runs the realism validator after Circuit IR
schematic parity and before ERC repair-loop verification, so the full workflow
cannot report `SCHEMATIC_VERIFIED` for composite caricature Circuit IR.

## Focused Test Command

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests \
  -only-testing:MerlinTests/KiCadSchematicParserTests \
  -only-testing:MerlinTests/AmpLowVoltageFixtureTests \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests
```

## Result

`TEST SUCCEEDED`

- Tests: 31
- Failures: 0

No full AmpDemo GUI demo was run.
