Status: complete

# Task 440b - Runtime ERC Repair Action

Date: 2026-05-30

## Goal

Implement the plugin-owned ERC repair action using the existing generic
`ERCRepairPlanner`.

## Implementation Scope

1. Add `kicad_repair_erc_from_diagnostics` to the electronics plugin manifest
   and KiCad tool definitions.
2. Route the runtime capability to an ERC repair handler.
3. Parse KiCad ERC JSON plus Circuit IR.
4. Emit an `erc_repair_plan` artifact and require `rerun_erc`.
5. Block unsupported diagnostics without claiming verification.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testERCRepairActionPlansSupportedDiagnosticsAndPreservesPatchArtifact \
  -only-testing:MerlinTests/ElectronicsRealRegistrationTests
```

Expected after Task 440b: ERC diagnostics have an explicit repair-plan action.
