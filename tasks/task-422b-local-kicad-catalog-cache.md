# Task 422b - Local KiCad Catalog Cache

Date: 2026-05-30

## Goal

Implement TTL-bound caching for extracted local KiCad symbol and footprint
catalogs.

## Implementation Scope

1. Store extracted catalogs in a stable plugin cache file.
2. Load cached catalogs when they are within TTL.
3. Fall back to extraction when cache is missing or stale.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests
```

Expected after Task 422b: cache tests pass.
