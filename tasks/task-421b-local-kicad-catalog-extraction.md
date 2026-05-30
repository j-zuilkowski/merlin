# Task 421b - Local KiCad Catalog Extraction

Date: 2026-05-30

## Goal

Implement local KiCad symbol and footprint extraction for the electronics
catalog path.

## Implementation Scope

1. Add a local KiCad catalog model for extracted symbols and footprints.
2. Add an extractor for `.kicad_sym` symbol roots.
3. Add an extractor for `.pretty/*.kicad_mod` footprint roots.
4. Keep parsing generic and library-qualified; do not add product-specific
   generators.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests
```

Expected after Task 421b: local KiCad catalog extraction tests pass.
