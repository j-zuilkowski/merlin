# Task 426b - Electronics Focused Cache Handoff

Date: 2026-05-30

## Goal

Complete the focused electronics runtime cache and handoff slice.

## Implementation Scope

1. Keep catalog extraction/cache in the electronics plugin path.
2. Keep provider config/cache in the electronics plugin path.
3. Keep handoff paths structured in `KiCadToolResult`.
4. Do not add hard-coded generators or product-specific shortcuts.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected after Task 426b: focused bundle passes.
