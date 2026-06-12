# Task 468b - Generic Multi-Board Decomposition Gates

## Goal

Wire generic board/domain decomposition evidence into Merlin's electronics
schema and runtime workflow path. This is a Merlin capability gate, not a
manual AmpDemo design split.

## Implementation

- Extended `BoardIntent` with optional per-board `VerificationPlan` evidence
  and `InterBoardConnectorIntent` records.
- Added schema validation that blocks KiCad mutation and downstream workflow
  advancement when hazardous mains/primary evidence and isolated low-voltage
  evidence are merged without separate board intents.
- Required mixed-domain designs to provide cross-board connector evidence and
  per-board verification plans.
- Added `CIRCUIT_IR_BOARD_UNKNOWN` validation so generated Circuit IR must
  reference a declared `DesignIntent` board.
- Updated the runtime DesignIntent builder to preserve explicit board connector
  evidence and to infer generic isolated-secondary plus mains-primary board
  domains when request text or constraints imply both domains.

## Focused Verification

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testGenericMultiboardDecompositionBlocksMergedMainsAndLowVoltageDomains \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testGenericMultiboardDecompositionPassesSeparatedDomainEvidence \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testCircuitIRBoardIDMustReferenceDesignIntentBoard \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowBlocksMergedHighStakesDomainsBeforeSchematicPCBOrFabAdvance \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowCarriesSeparatedBoardDomainEvidenceThroughHandoff
```

Result: `TEST SUCCEEDED`, 5 tests, 0 failures.

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testAmpDemoSpecFileBuildsMeaningfulDesignIntent \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testStructuredConstraintsPopulateDesignIntentInsteadOfEmptyDraft \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testConstraintOnlyPayloadSynthesizesReusableClassATopologyEvidence
```

Result: `TEST SUCCEEDED`, 3 tests, 0 failures.

## Remaining Scope

This task does not complete arbitrary electronics synthesis. It establishes the
generic decomposition evidence gate and runtime handoff. Remaining work is still
needed for topology/materialization realism, ERC/DRC repair loops, vendor/BOM
evidence, fabrication packaging, and GUI job-state consistency before a full
AmpDemo GUI demo should be run.
