# Task 431b - Focused Amp Backend Handoff

Date: 2026-05-30

## Goal

Complete the focused Amp backend slice without adding a hard-coded generator.

## Implementation Scope

1. Apply local KiCad footprint enrichment to explicit catalog candidates.
2. Preserve candidate provenance and target-refdes evidence.
3. Carry Circuit IR pin-to-pad mappings into footprint validation.
4. Keep the slice generic for any Circuit IR-backed design.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testFocusedAmpBackendSliceUsesCatalogConfigHandoffAndCreatesKiCadArtifacts
```

Expected after Task 431b: focused Amp backend handoff passes.
