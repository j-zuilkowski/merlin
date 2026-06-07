# Task 471a - DRC Layout Rerun Evidence Tests

## Goal

Add fail-first tests proving Merlin cannot advance PCB or fabrication workflow
from a DRC repair plan, a missing rerun report, or a recorded patch application
without concrete PCB/layout mutation evidence.

## Tests Added

- `PCBDRCFollowOnTests.testDRCRepairLoopRequiresExplicitRerunReport` verifies an
  empty DRC report sequence blocks with `DRC_RERUN_REPORT_REQUIRED`.
- `PCBDRCFollowOnTests.testPCBVerificationBlocksRepairPlanWithoutLayoutMutationEvidence`
  verifies PCB verification blocks when a repair path requires layout mutation
  evidence but none exists.
- `ElectronicsEndToEndHarnessTests.testWorkflowRequiresLayoutMutationEvidenceBeforeDRCRerunCanVerifyPCB`
  verifies the full harness blocks PCB and fabrication advancement from
  repair-required PCB evidence that lacks layout mutation evidence.
- `ElectronicsToolFailureEvidenceTests.testDRCRepairPatchApplicationRecordsUnverifiedLayoutMutationRequirement`
  verifies `kicad_apply_drc_repair_patch` records an unverified repair
  application that requires a concrete PCB/layout mutation before DRC rerun can
  be accepted as workflow evidence.

## Fail-First Evidence

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/PCBDRCFollowOnTests/testDRCRepairLoopRequiresExplicitRerunReport \
  -only-testing:MerlinTests/PCBDRCFollowOnTests/testPCBVerificationBlocksRepairPlanWithoutLayoutMutationEvidence \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresLayoutMutationEvidenceBeforeDRCRerunCanVerifyPCB \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationRecordsUnverifiedLayoutMutationRequirement
```

Result: `TEST FAILED` at compile time. `PCBVerificationEvidence` had no
layout-mutation evidence fields, `PCBVerificationEvidenceKey` had no
`layout_mutation_evidence` key, and the current DRC loop still accepted empty
report sequences as clean verification.
