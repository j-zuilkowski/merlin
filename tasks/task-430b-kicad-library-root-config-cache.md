# Task 430b - KiCad Library Root Config Cache

Date: 2026-05-30

## Goal

Wire KiCad library root discovery and TTL caching into runtime electronics
component selection.

## Implementation Scope

1. Accept root search paths and cache settings from provider config.
2. Let request payload values override config values.
3. Cache discovered roots after validation.
4. Use discovered roots for local KiCad catalog extraction when explicit roots
   are absent.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected after Task 430b: runtime root discovery and cache tests pass.
