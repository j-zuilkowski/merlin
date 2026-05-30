# Task 442b - Runtime DRC Repair Action

Date: 2026-05-30

## Goal

Implement the plugin-owned DRC repair action using the existing generic
`PCBDRCRepairLoop` planner behavior.

## Implementation Scope

1. Add `kicad_repair_drc_from_diagnostics` to the electronics plugin manifest
   and KiCad tool definitions.
2. Route the runtime capability to a DRC repair handler.
3. Parse KiCad DRC JSON.
4. Emit a `drc_repair_plan` artifact for supported repair classes.
5. Block unsupported or approval-required diagnostics without claiming DRC
   verification.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairActionPlansSupportedDiagnosticsAndBlocksApprovalRequiredDiagnostics \
  -only-testing:MerlinTests/ElectronicsRealRegistrationTests
```

Expected after Task 442b: DRC diagnostics have an explicit repair-plan action.
