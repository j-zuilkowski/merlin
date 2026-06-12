# Task 436b - Diagnostic Artifact Preservation

Date: 2026-05-30

## Goal

Preserve validation and simulation artifacts even when the gate fails.

## Implementation Scope

1. Attach ERC/DRC report artifacts on blocked validation.
2. Attach SPICE log artifacts on blocked simulation.
3. Return workspace artifact references for blocked results.
4. Keep artifacts available for later repair loops.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadERCGateBlocksOnParsedBlockingDiagnostics \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadDRCGateBlocksOnParsedBlockingDiagnostics \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOnNgspiceErrorsAndPreservesRepairDiagnostics
```

Expected after Task 436b: failed validation artifacts are preserved.
