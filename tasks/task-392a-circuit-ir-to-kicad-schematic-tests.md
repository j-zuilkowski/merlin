# Task 392a - Circuit IR to KiCad schematic tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#kicad-integration-strategy
- Roadmap reference: plugins/electronics/tasks.md#phase-5-circuit-ir-to-kicad-schematic-materialization

## Behavior

Validated Circuit IR SHALL materialize into KiCad schematic artifacts through
structured parser/writer APIs, not product-specific raw string generation.

## Red Tests

- Add `.kicad_sch` parser/writer round-trip tests.
- Add tests that valid Circuit IR creates `.kicad_pro` and `.kicad_sch`.
- Add parity tests proving Circuit IR components and nets match the schematic.
- Add source-level guard tests against product-specific schematic emitters.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests
```

Expected red state: tests fail because Circuit IR is not compiled through a
structured KiCad schematic writer.

## Commit

Stage only schematic materialization tests and fixtures.
