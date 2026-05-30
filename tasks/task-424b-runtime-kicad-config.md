# Task 424b - Runtime KiCad Config

Date: 2026-05-30

## Goal

Wire local KiCad catalog extraction/cache into runtime component selection.

## Implementation Scope

1. Accept local KiCad library roots through payload/config.
2. Load fresh cached local KiCad catalog data when available.
3. Extract and cache local KiCad catalog data when cache is missing or stale.
4. Use extracted symbol/footprint evidence when enriching provider candidates.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected after Task 424b: runtime KiCad config/cache tests pass.
