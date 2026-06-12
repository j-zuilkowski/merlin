# Task 472b - DRC Layout Mutators

## Goal

Implement bounded, generic PCB/layout mutations for DRC repair plans so Merlin
can move from repair-plan evidence to concrete board changes before requiring a
fresh DRC rerun.

## Implementation

- `kicad_apply_drc_repair_patch` now derives the sibling `.kicad_pcb` board,
  reads the board before mutation, applies supported generic repair patches,
  writes the mutated board, and blocks with `regenerate_drc_repair_plan` when
  no concrete board changes can be mapped.
- Placement repairs move targeted footprints by reference while preserving the
  footprint node shape.
- Clearance repairs update board/net-class clearance rules to a bounded minimum.
- Net-class repairs update trace-width rules to a bounded minimum.
- Routing repairs add a KiCad board comment marker documenting the net that
  requires reroute before DRC rerun.
- Runtime output now emits both `drc_repair_application` and
  `layout_mutation_evidence` artifacts. Mutation evidence records source plan,
  project, board path, before/after SHA-256 hashes, patch IDs, changed objects,
  `verified: false`, and `requires_rerun_tool: "kicad_run_drc"`.
- DRC repair application status is now `patch_applied_requires_drc_rerun`,
  `requires_layout_mutation: false`, and `nextActions == ["kicad_run_drc"]`.

## Focused Verification

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testRepairPatchApplicationRequiresGateRerunBeforeAdvancement \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowAcceptsCleanDRCRerunAfterConcreteLayoutMutationEvidence
```

Result: `TEST SUCCEEDED`, 3 tests, 0 failures.

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairActionPlansSupportedDiagnosticsAndBlocksApprovalRequiredDiagnostics \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testRepairPatchApplicationRequiresGateRerunBeforeAdvancement \
  -only-testing:MerlinTests/PCBDRCFollowOnTests/testPCBVerificationBlocksRepairPlanWithoutLayoutMutationEvidence \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresLayoutMutationEvidenceBeforeDRCRerunCanVerifyPCB \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowAcceptsCleanDRCRerunAfterConcreteLayoutMutationEvidence
```

Result: `TEST SUCCEEDED`, 6 tests, 0 failures.

## Remaining Scope

Routing repair is still a bounded evidence marker, not a KiCad-native autoroute
or segment/via rewrite. This task advances generic Merlin DRC repair behavior;
it does not hand-author any sample-project board split, vendor/BOM evidence,
fabrication packaging, GUI job-state consistency, or a full AmpDemo GUI run.
