# Task 432a - Focused Amp Artifact Creation Tests

Date: 2026-05-30

## Goal

Add focused tests proving the Amp backend slice creates real KiCad artifacts
only after selection and footprint evidence succeed.

## Test Scope

1. Compile from DesignIntent, Circuit IR, component matrix, and footprint
   assignment paths.
2. Assert project, schematic, and board artifacts are returned.
3. Assert schematic content includes concrete fixture refdes values.
4. Keep artifact creation behind evidence gates.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testFocusedAmpBackendSliceUsesCatalogConfigHandoffAndCreatesKiCadArtifacts
```

Expected before Task 432b: the focused slice does not prove artifact creation
from handoff evidence.
