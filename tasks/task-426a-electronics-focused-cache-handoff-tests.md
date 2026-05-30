# Task 426a - Electronics Focused Cache Handoff Tests

Date: 2026-05-30

## Goal

Add a focused regression bundle proving catalog extraction, provider config,
provider cache, local KiCad cache, and artifact handoff work together in the
electronics runtime slice.

## Test Scope

1. Run component selection through runtime provider config.
2. Verify provider cache reuse when a fixture disappears.
3. Verify local KiCad footprint enrichment from extracted libraries.
4. Verify handoff paths can drive the footprint assignment step.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected before Task 426b: the focused bundle fails on missing runtime cache or
handoff behavior.
