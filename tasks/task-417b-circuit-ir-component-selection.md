# Task 417b - Circuit IR Component Selection

## Goal

Implement Circuit IR-aware component selection so expanded schematic parts drive
the component matrix.

## Implementation

1. Read optional `circuit_ir_path` in `kicad_select_components`.
2. Prefer Circuit IR components over DesignIntent components when Circuit IR is
   present.
3. Map Circuit IR pins and symbols into component selection constraints.
4. Filter fixture catalog candidates by component category/refdes class before
   selecting.
5. Preserve existing DesignIntent-only behavior when no Circuit IR is supplied.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected: tests pass.
