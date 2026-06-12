# Task 423b - Provider Config Cache

Date: 2026-05-30

## Goal

Implement plugin-owned runtime catalog provider configuration and provider
candidate caching.

## Implementation Scope

1. Read provider fixture paths from explicit request config or workspace-local
   `.merlin/electronics-provider-config.json`.
2. Let request payload fields override config values.
3. Cache mapped Digi-Key/Mouser/aggregator provider candidates by provider ID.
4. Load provider candidates from cache when the original fixture is unavailable
   and the cache is within TTL.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected after Task 423b: provider config/cache tests pass.
