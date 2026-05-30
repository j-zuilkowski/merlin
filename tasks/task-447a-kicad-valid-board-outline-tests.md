# Task 447a - KiCad-Valid Board Outline Tests

Date: 2026-05-30

## Goal

Add focused tests proving runtime board artifacts include a valid minimal
Edge.Cuts outline and pass real KiCad DRC when the CLI is available.

## Test Scope

1. Runtime compile output includes a board artifact.
2. The board artifact declares an `Edge.Cuts` layer.
3. The board artifact contains a closed board outline.
4. The compiled board passes real `kicad-cli pcb drc` when KiCad is installed.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testCleanBackendAmpValidationSliceCompilesAndRunsPassingERCSPICEDRC \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testCompiledBoardOutlinePassesRealKiCadDRCWhenAvailable
```

Expected before Task 447b: generated board output can fail DRC with an invalid
or missing outline.
