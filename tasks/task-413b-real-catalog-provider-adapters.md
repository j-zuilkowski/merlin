# Task 413b — Real Catalog Provider Adapters

## Goal

Add optional real provider adapters for component, availability, datasheet, and
CAD model evidence.

## Implementation

1. Add Digi-Key provider adapter.
2. Add Mouser provider adapter.
3. Add optional Nexar/Octopart or equivalent aggregator adapter.
4. Add optional CAD model provider adapter hooks for SnapMagic/SnapEDA, Ultra
   Librarian, SamacSys, or equivalent sources.
5. Add provider configuration and credential validation.
6. Add TTL cache and provenance metadata.
7. Keep recorded fixture tests offline.
8. Make live provider tests opt-in.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/RealCatalogProviderAdaptersTests
```

Expected: tests pass without live API credentials by using recorded fixtures.
