# Task 435a - Diagnostic Repair Routing Tests

Date: 2026-05-30

## Goal

Add failing tests proving parsed ERC/DRC diagnostics are returned as structured
repair inputs.

## Test Scope

1. ERC blocking diagnostics become `KiCadViolation` entries.
2. DRC blocking diagnostics become `KiCadViolation` entries.
3. Warning codes preserve the original diagnostic code.
4. Next actions point to diagnostic-driven repair, not generic progress.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadERCGateBlocksOnParsedBlockingDiagnostics \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadDRCGateBlocksOnParsedBlockingDiagnostics
```

Expected before Task 435b: diagnostics are attached as generic command failures
or not parsed.
