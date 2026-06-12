# Task 429a - KiCad Library Root Discovery Tests

Date: 2026-05-30

## Goal

Add failing tests proving the electronics plugin can discover real KiCad symbol
and footprint library roots from a configured install layout.

## Test Scope

1. Discover `symbols` and `footprints` below a KiCad app support layout.
2. Return concrete root paths only when both directories exist.
3. Keep discovery independent of a specific demo design.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests
```

Expected before Task 429b: no library-root discovery contract exists.
