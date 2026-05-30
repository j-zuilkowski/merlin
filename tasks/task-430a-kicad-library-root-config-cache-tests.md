# Task 430a - KiCad Library Root Config Cache Tests

Date: 2026-05-30

## Goal

Add failing tests proving runtime component selection can use configured KiCad
root discovery and cache discovered roots with a TTL.

## Test Scope

1. Read `kicad_library_root_search_paths` from electronics provider config.
2. Cache discovered symbol and footprint roots.
3. Reuse only fresh root-cache entries.
4. Use discovered roots to enrich selected parts with local KiCad footprint
   evidence.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected before Task 430b: runtime discovery config/cache is not wired.
