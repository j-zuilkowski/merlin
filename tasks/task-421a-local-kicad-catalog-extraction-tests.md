# Task 421a - Local KiCad Catalog Extraction Tests

Date: 2026-05-30

## Goal

Add failing tests proving the electronics plugin can extract local KiCad symbol
and footprint library data instead of relying only on hand-authored JSON
catalog fixtures.

## Test Scope

1. Parse `.kicad_sym` files into `KiCadSymbolDefinition` values.
2. Parse `.pretty/*.kicad_mod` footprint trees into `KiCadFootprintDefinition`
   values.
3. Preserve KiCad library-qualified names such as `Device:R` and
   `Resistor_SMD:R_0603_1608Metric`.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests
```

Expected before Task 421b: extraction tests fail because the extractor does not
exist.
