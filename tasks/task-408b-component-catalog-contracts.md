# Task 408b — Component Catalog Contracts

## Goal

Add the electronics-plugin component catalog schemas, Swift models, validators,
and offline provider abstraction.

## Implementation

1. Add plugin-owned schemas under `plugins/electronics/schemas`.
2. Add runtime models only where Merlin needs to read or emit the artifacts.
3. Add `ComponentCatalogProvider` abstraction.
4. Add `StaticFixtureCatalogProvider` for tests.
5. Add a local KiCad library provider contract for symbol/footprint discovery.
6. Preserve provider ID, source URL/path, retrieval timestamp, cache policy, and
   evidence hashes where available.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests
```

Expected: tests pass.
