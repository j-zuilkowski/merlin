# Task 439a - Runtime ERC Repair Action Tests

Date: 2026-05-30

## Goal

Add focused tests proving the electronics runtime exposes an ERC repair action
that turns KiCad ERC diagnostics into a concrete repair-plan artifact.

## Test Scope

1. `kicad_repair_erc_from_diagnostics` requires an ERC report and Circuit IR.
2. Supported ERC diagnostics produce an `erc_repair_plan` artifact.
3. Unsupported ERC diagnostics block and require engineering review.
4. The repair action must not mark ERC verification complete; it must route to
   `rerun_erc`.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testERCRepairActionPlansSupportedDiagnosticsAndPreservesPatchArtifact
```

Expected before Task 440b: no runtime ERC repair action exists.
