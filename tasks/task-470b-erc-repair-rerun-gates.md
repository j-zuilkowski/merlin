# Task 470b - ERC Repair Rerun Gates

## Goal

Wire ERC rerun evidence into the repair loop, full workflow harness, and
runtime patch-application artifacts so schematic verification cannot advance
from narrative repair claims or implied clean reports.

## Implementation

- `ERCRepairLoop` now blocks empty ERC report sequences with
  `ERC_RERUN_REPORT_REQUIRED` and zero repair attempts.
- `ElectronicsEndToEndHarness` now passes actual ERC evidence into the repair
  loop, leaves `erc_report` missing when no report exists, and carries repair
  loop diagnostics into the schematic verification result.
- `kicad_apply_erc_repair_patch` now writes a
  `patch_applied_requires_rerun` artifact with `verified: false` and
  `requires_rerun_tool: kicad_run_erc`.
- Shared repair application artifacts now use stable snake-case evidence keys
  and explicitly record `verified: false` until the relevant rerun tool
  produces clean evidence.

## Focused Verification

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ERCRepairLoopTests/testRepairLoopRequiresExplicitERCRerunReport \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresExplicitERCRerunReportBeforeSchematicVerified \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testERCRepairPatchApplicationRecordsUnverifiedRerunRequirement
```

Result: `TEST SUCCEEDED`, 3 tests, 0 failures.

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ERCRepairLoopTests \
  -only-testing:MerlinTests/SchematicVerifiedStatusTests \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testERCRepairActionPlansSupportedDiagnosticsAndPreservesPatchArtifact
```

Result: `TEST SUCCEEDED`, 16 tests, 0 failures.

## Remaining Scope

This does not finish DRC/layout repair reruns, vendor/BOM evidence,
fabrication packaging, GUI job-state consistency, or a full AmpDemo GUI run.
