# Task 433a - KiCad CLI Validation Gate Tests

Date: 2026-05-30

## Goal

Add failing tests proving ERC and DRC are judged from real `kicad-cli` report
contents, not just command execution.

## Test Scope

1. `kicad_run_erc` invokes `kicad-cli sch erc`.
2. `kicad_run_drc` invokes `kicad-cli pcb drc`.
3. Blocking report diagnostics return blocked tool results.
4. ERC/DRC report artifacts are preserved for inspection and repair.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadERCGateBlocksOnParsedBlockingDiagnostics \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadDRCGateBlocksOnParsedBlockingDiagnostics
```

Expected before Task 433b: report contents do not block advancement.
