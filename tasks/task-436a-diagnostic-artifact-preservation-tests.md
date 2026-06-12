# Task 436a - Diagnostic Artifact Preservation Tests

Date: 2026-05-30

## Goal

Add failing tests proving failed validation commands preserve diagnostic
artifacts.

## Test Scope

1. ERC failures return an `erc_report` artifact.
2. DRC failures return a `drc_report` artifact.
3. SPICE failures return a `spice_measurements` artifact.
4. Returned artifact paths exist on disk.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadERCGateBlocksOnParsedBlockingDiagnostics \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadDRCGateBlocksOnParsedBlockingDiagnostics \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOnNgspiceErrorsAndPreservesRepairDiagnostics
```

Expected before Task 436b: failed validation artifacts are not consistently
preserved.
