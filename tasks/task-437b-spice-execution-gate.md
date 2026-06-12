# Task 437b - SPICE Execution Gate

Date: 2026-05-30

## Goal

Make ngspice execution errors block with preserved log artifacts and
repair-specific next actions.

## Implementation Scope

1. Run configured ngspice in batch mode.
2. Preserve output logs on failure.
3. Return `blockedSimulation` status on execution failure.
4. Route next action to SPICE diagnostic repair.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOnNgspiceErrorsAndPreservesRepairDiagnostics
```

Expected after Task 437b: SPICE execution failures block with diagnostics.
