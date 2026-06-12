# Task 472a - DRC Layout Mutator Tests

## Goal

Add fail-first coverage proving DRC repair patch application must mutate KiCad
PCB/layout artifacts and emit mutation evidence before DRC rerun can be the
next workflow action.

## Tests Added

- `ElectronicsToolFailureEvidenceTests.testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence`
  verifies `kicad_apply_drc_repair_patch` handles generic placement,
  clearance, net-class, and routing repair patches by changing the PCB file,
  emitting `layout_mutation_evidence`, recording before/after hashes, patch IDs,
  and changed objects, and requiring `kicad_run_drc` next.
- `ElectronicsToolFailureEvidenceTests.testRepairPatchApplicationRequiresGateRerunBeforeAdvancement`
  verifies the combined ERC, DRC, and SPICE repair gate sequence still blocks
  advancement until explicit rerun evidence exists, with DRC patch application
  now producing mutation evidence instead of a narrative mutation requirement.
- `ElectronicsEndToEndHarnessTests.testWorkflowAcceptsCleanDRCRerunAfterConcreteLayoutMutationEvidence`
  verifies the full harness accepts a clean DRC rerun only when concrete
  layout-mutation evidence exists for the repaired PCB path.

## Fail-First Evidence

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testRepairPatchApplicationRequiresGateRerunBeforeAdvancement \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowAcceptsCleanDRCRerunAfterConcreteLayoutMutationEvidence
```

Result: `TEST FAILED`. The new DRC patch test could not unwrap a
`layout_mutation_evidence` artifact, and the existing full repair-gate test
still reported `nextActions == ["apply_pcb_layout_mutation", "kicad_run_drc"]`
with the old `DRC_PATCH_REQUIRES_BOARD_MUTATOR` warning. The harness test with
pre-existing layout-mutation evidence already passed, proving the remaining gap
was runtime mutation/evidence wiring.
