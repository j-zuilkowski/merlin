# Task 432b - Focused Amp Artifact Creation

Date: 2026-05-30

## Goal

Finish the focused Amp backend slice by compiling evidence-gated inputs into
KiCad project artifacts.

## Implementation Scope

1. Require all compile inputs to come from verified handoff paths.
2. Produce KiCad project, schematic, and board artifacts.
3. Preserve the generic runtime compile path.
4. Do not bypass ERC/DRC/SPICE gates for later full-demo stages.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testFocusedAmpBackendSliceUsesCatalogConfigHandoffAndCreatesKiCadArtifacts
```

Expected after Task 432b: focused Amp artifact creation passes.
