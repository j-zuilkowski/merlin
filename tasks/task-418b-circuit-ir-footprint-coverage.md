# Task 418b - Circuit IR Footprint Coverage

## Goal

Implement Circuit IR-aware footprint assignment coverage before compile can
consume generated footprint evidence.

## Implementation

1. Read optional `circuit_ir_path` in `kicad_assign_footprints`.
2. Prefer Circuit IR components as the footprint assignment target set when
   Circuit IR is present.
3. Use Circuit IR pin evidence for pin/pad matching.
4. Block if any Circuit IR component lacks a selected component matrix row.
5. Preserve DesignIntent-only footprint assignment behavior without Circuit IR.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FootprintEvidenceGateTests \
  -only-testing:MerlinTests/CompileGateEvidenceTests
```

Expected: tests pass.
