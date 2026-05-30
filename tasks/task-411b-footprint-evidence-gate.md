# Task 411b — Footprint Evidence Gate

## Goal

Make footprint assignment evidence-backed and block incompatible or unresolved
footprints.

## Implementation

1. Read `ComponentMatrix`.
2. Query local KiCad/CAD catalog footprint providers.
3. Extract or consume footprint pad maps.
4. Match symbol pins to footprint pads.
5. Emit footprint assignment artifact with source provenance.
6. Block unresolved or incompatible assignments.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FootprintEvidenceGateTests
```

Expected: tests pass.
