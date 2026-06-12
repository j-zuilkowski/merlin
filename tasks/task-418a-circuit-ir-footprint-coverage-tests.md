# Task 418a - Circuit IR Footprint Coverage Tests

## Goal

Add focused tests proving footprint assignment covers every PCB-bound Circuit IR
component and cannot advance with missing expanded parts.

## Failing Tests

Add focused tests proving:

1. `kicad_assign_footprints` accepts `circuit_ir_path`.
2. Footprint assignments are emitted for expanded Circuit IR refdes.
3. Circuit IR pin evidence drives pin/pad compatibility checks.
4. Missing matrix decisions for Circuit IR components block with affected
   refdes.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FootprintEvidenceGateTests
```

Expected: tests fail before Task 418b.
