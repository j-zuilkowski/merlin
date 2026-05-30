# Task 424a - Runtime KiCad Config Tests

Date: 2026-05-30

## Goal

Add failing tests proving runtime component selection can discover local KiCad
symbol and footprint roots through request/config fields, extract them, and
cache them for later calls.

## Test Scope

1. Supply `kicad_symbol_library_root` and `kicad_footprint_library_root`.
2. Supply `kicad_catalog_cache_directory` and TTL.
3. Verify selected provider candidates receive local KiCad footprint evidence.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected before Task 424b: runtime KiCad config/cache tests fail.
