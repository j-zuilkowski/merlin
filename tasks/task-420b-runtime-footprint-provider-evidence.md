# Task 420b - Runtime Footprint Provider Evidence

## Goal

Wire local KiCad footprint evidence into runtime catalog selection so selected
vendor candidates can satisfy downstream footprint coverage gates.

## Implementation

1. Read optional local KiCad symbol and footprint catalog paths.
2. Use Circuit IR selected symbol/footprint constraints to request local KiCad
   footprint evidence.
3. Attach local footprint candidates to matching vendor candidates without
   weakening datasheet/provenance validation.
4. Keep footprint assignment blocked when selected candidates still lack
   footprint evidence.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests \
  -only-testing:MerlinTests/FootprintEvidenceGateTests \
  -only-testing:MerlinTests/CompileGateEvidenceTests
```

Expected: tests pass.
