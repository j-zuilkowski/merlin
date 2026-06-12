# Task 420a - Runtime Footprint Provider Evidence Tests

## Goal

Add focused tests proving runtime-selected provider candidates can carry local
KiCad footprint evidence into footprint assignment.

## Failing Tests

Add focused tests proving:

1. Runtime selection accepts local KiCad symbol and footprint catalog paths.
2. Provider candidates with datasheet/procurement evidence are enriched with
   local footprint candidates when Circuit IR names the selected footprint.
3. `kicad_assign_footprints` can consume that provider-generated matrix and
   emit complete footprint coverage for the Circuit IR component.
4. Missing footprint catalog evidence still blocks at footprint assignment.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests \
  -only-testing:MerlinTests/FootprintEvidenceGateTests
```

Expected: tests fail before Task 420b.
