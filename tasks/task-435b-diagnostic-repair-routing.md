# Task 435b - Diagnostic Repair Routing

Date: 2026-05-30

## Goal

Route parsed ERC/DRC diagnostics into repair-specific runtime outputs.

## Implementation Scope

1. Convert parsed report errors into `KiCadViolation` entries.
2. Preserve diagnostic codes in warnings.
3. Return repair-specific next actions.
4. Keep original report artifacts attached.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadERCGateBlocksOnParsedBlockingDiagnostics \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadDRCGateBlocksOnParsedBlockingDiagnostics
```

Expected after Task 435b: ERC/DRC diagnostics are structured repair inputs.
