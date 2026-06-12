# Task 431a - Focused Amp Backend Handoff Tests

Date: 2026-05-30

## Goal

Add a focused Amp backend regression proving component selection, footprint
assignment, and compile are chained by handoff evidence.

## Test Scope

1. Use the plugin-owned Amp low-voltage fixture.
2. Select components from explicit catalog evidence.
3. Enrich explicit candidates with local KiCad footprint evidence.
4. Pass handoff paths into footprint assignment and compile.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testFocusedAmpBackendSliceUsesCatalogConfigHandoffAndCreatesKiCadArtifacts
```

Expected before Task 431b: explicit candidate files do not receive local KiCad
footprint evidence.
