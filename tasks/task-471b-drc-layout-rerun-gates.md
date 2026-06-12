# Task 471b - DRC Layout Rerun Gates

## Goal

Wire DRC/layout rerun evidence into the repair loop, PCB verification gate,
full workflow harness, and runtime repair application artifact path so PCB and
fabrication status cannot advance from repair-plan claims alone.

## Implementation

- `PCBDRCRepairLoop` now blocks empty DRC report sequences with
  `DRC_RERUN_REPORT_REQUIRED` instead of treating them as clean reruns.
- `PCBVerificationEvidence` now carries `requiresLayoutMutationEvidence` and
  `layoutMutationEvidencePath`, with flexible snake-case decoding.
- `PCBVerificationGate` now blocks with `DRC_LAYOUT_MUTATION_REQUIRED` and
  missing `layout_mutation_evidence` when a repaired DRC path lacks an existing
  PCB/layout mutation evidence file.
- `ElectronicsEvidenceArtifactPaths` can carry `layoutMutationEvidencePath`
  forward into PCB evidence.
- `kicad_apply_drc_repair_patch` now records
  `patch_recorded_requires_layout_mutation`, `verified: false`,
  `requires_rerun_tool: kicad_run_drc`, and `requires_layout_mutation: true`.
  Its next actions now include `apply_pcb_layout_mutation` before
  `kicad_run_drc`.

## Focused Verification

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/PCBDRCFollowOnTests/testDRCRepairLoopRequiresExplicitRerunReport \
  -only-testing:MerlinTests/PCBDRCFollowOnTests/testPCBVerificationBlocksRepairPlanWithoutLayoutMutationEvidence \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresLayoutMutationEvidenceBeforeDRCRerunCanVerifyPCB \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationRecordsUnverifiedLayoutMutationRequirement
```

Result: `TEST SUCCEEDED`, 4 tests, 0 failures.

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/PCBDRCFollowOnTests \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairActionPlansSupportedDiagnosticsAndBlocksApprovalRequiredDiagnostics \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testRepairPatchApplicationRequiresGateRerunBeforeAdvancement \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationRecordsUnverifiedLayoutMutationRequirement \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresLayoutMutationEvidenceBeforeDRCRerunCanVerifyPCB \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowCarriesSeparatedBoardDomainEvidenceThroughHandoff \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testBlockingDRCViolationBlocksPCBAndHarness
```

Result: `TEST SUCCEEDED`, 16 tests, 0 failures.

## Remaining Scope

This gates DRC repair-plan honesty; it does not implement a generic PCB/layout
mutator, autorouter repair action, vendor/BOM evidence, fabrication packaging,
GUI job-state consistency, or a full AmpDemo GUI run.
