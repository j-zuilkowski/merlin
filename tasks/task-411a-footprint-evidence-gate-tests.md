# Task 411a — Footprint Evidence Gate Tests

## Goal

Prevent PCB-bound workflow steps from advancing without footprint provenance and
symbol-pin to footprint-pad compatibility evidence.

## Failing Tests

Add focused tests proving:

1. `kicad_assign_footprints` blocks when no component matrix exists.
2. `kicad_assign_footprints` blocks when selected components have no footprint
   candidate.
3. Pin/pad mismatches block with affected refdes and candidate footprint.
4. Fixture provider footprint evidence can produce a footprint assignment
   artifact.
5. The assignment artifact preserves footprint source provenance.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FootprintEvidenceGateTests
```

Expected: tests fail before Task 411b.
