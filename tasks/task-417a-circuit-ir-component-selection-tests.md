# Task 417a - Circuit IR Component Selection Tests

## Goal

Add focused tests proving component selection uses expanded Circuit IR
components instead of block-level DesignIntent placeholders.

## Failing Tests

Add focused tests proving:

1. `kicad_select_components` accepts `circuit_ir_path`.
2. Component decisions are emitted for Circuit IR refdes such as `RFILT1` and
   `CFILT1`.
3. Block-level placeholders such as `FILTER1` are not treated as selected
   component rows when Circuit IR exists.
4. Missing catalog evidence leaves Circuit IR components in
   `requires_vendor_resolution`, not false selection.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected: tests fail before Task 417b.
