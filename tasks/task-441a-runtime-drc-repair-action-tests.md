Status: complete

# Task 441a - Runtime DRC Repair Action Tests

Date: 2026-05-30

## Goal

Add focused tests proving the electronics runtime exposes a DRC repair action
that produces repair plans for supported PCB diagnostics and blocks approval
required changes.

## Test Scope

1. `kicad_repair_drc_from_diagnostics` requires a DRC report.
2. Supported DRC diagnostics produce a `drc_repair_plan` artifact.
3. Layer-count or fabricator-profile changes block with
   `DRC_REPAIR_REQUIRES_APPROVAL`.
4. The repair action must route to `rerun_drc`.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairActionPlansSupportedDiagnosticsAndBlocksApprovalRequiredDiagnostics
```

Expected before Task 442b: no runtime DRC repair action exists.
