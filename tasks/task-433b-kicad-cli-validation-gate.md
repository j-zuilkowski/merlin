# Task 433b - KiCad CLI Validation Gate

Date: 2026-05-30

## Goal

Make ERC and DRC runtime gates use parsed `kicad-cli` report contents.

## Implementation Scope

1. Keep invoking the configured `kicad-cli` executable.
2. Parse ERC and DRC JSON report artifacts.
3. Block on parsed error-severity diagnostics.
4. Preserve report artifacts and route next actions to repair.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadERCGateBlocksOnParsedBlockingDiagnostics \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadDRCGateBlocksOnParsedBlockingDiagnostics
```

Expected after Task 433b: ERC and DRC blocking reports fail the gate.
