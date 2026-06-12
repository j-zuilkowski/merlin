# Task 437a - SPICE Execution Gate Tests

Date: 2026-05-30

## Goal

Add failing tests proving ngspice execution errors block simulation-required
workflows with useful diagnostics.

## Test Scope

1. `kicad_run_spice` requires a runnable SPICE deck.
2. ngspice non-zero exit blocks the tool result.
3. The ngspice output log is preserved as `spice_measurements`.
4. The returned next action routes to SPICE repair.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOnNgspiceErrorsAndPreservesRepairDiagnostics
```

Expected before Task 437b: SPICE failures do not produce repair-specific
diagnostics.
