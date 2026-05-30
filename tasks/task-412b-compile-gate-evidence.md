# Task 412b — Compile Gate Evidence

## Goal

Tighten `kicad_compile_project` so generated KiCad artifacts require real
design, component, and footprint evidence.

## Implementation

1. Require approved DesignIntent for natural-language-originated work.
2. Require Circuit IR.
3. Require ComponentMatrix.
4. Require footprint assignment for PCB-bound components.
5. Keep user-authored/test-fixture exceptions explicit and narrow.
6. Return blocked diagnostics instead of skeleton schematic/PCB artifacts when
   evidence is missing.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CompileGateEvidenceTests \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests
```

Expected: tests pass.
