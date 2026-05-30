# Task 422a - Local KiCad Catalog Cache Tests

Date: 2026-05-30

## Goal

Add failing tests proving extracted local KiCad catalogs can be cached and
invalidated by TTL.

## Test Scope

1. Write an extracted symbol/footprint catalog to a plugin-owned cache file.
2. Load the cache while it is within TTL.
3. Ignore the cache after TTL expiry.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests
```

Expected before Task 422b: cache tests fail because the cache reader/writer does
not exist.
