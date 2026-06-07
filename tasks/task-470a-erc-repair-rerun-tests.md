# Task 470a - ERC Repair Rerun Evidence Tests

## Goal

Add fail-first tests proving Merlin cannot advance schematic verification from
an implied clean ERC run or from an applied repair patch without an explicit
KiCad ERC rerun report.

## Tests Added

- `ERCRepairLoopTests.testRepairLoopRequiresExplicitERCRerunReport` verifies an
  empty ERC report sequence blocks with `ERC_RERUN_REPORT_REQUIRED` instead of
  being treated as clean verification.
- `ElectronicsEndToEndHarnessTests.testWorkflowRequiresExplicitERCRerunReportBeforeSchematicVerified`
  verifies the full harness blocks schematic verification when ERC evidence is
  absent and surfaces the rerun-report diagnostic.
- `ElectronicsToolFailureEvidenceTests.testERCRepairPatchApplicationRecordsUnverifiedRerunRequirement`
  verifies `kicad_apply_erc_repair_patch` records an unverified patch
  application artifact and does not hand off a fabricated ERC report path.

## Fail-First Evidence

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ERCRepairLoopTests/testRepairLoopRequiresExplicitERCRerunReport \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresExplicitERCRerunReportBeforeSchematicVerified \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testERCRepairPatchApplicationRecordsUnverifiedRerunRequirement
```

Result: `TEST FAILED`. Empty ERC report sequences were treated as clean
verification, patch application artifacts reported `patch_applied` without an
explicit `verified: false` / `requires_rerun_tool` record, and the full harness
did not surface `ERC_RERUN_REPORT_REQUIRED`.
