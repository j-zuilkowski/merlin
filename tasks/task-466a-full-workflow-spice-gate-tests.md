# Task 466a - Full Workflow SPICE Evidence Gate Tests

## Goal

Prove the structured electronics workflow path cannot advance SPICE from
narrative claims, missing model-record evidence, missing measurement envelopes,
or a generic smoke deck.

## Requirements

1. `workflow.requirements_to_pcb` must block artifact-path evidence when the
   ngspice log contains only narrative success text.
2. `workflow.requirements_to_pcb` must block when a SPICE scenario requires
   models but no `spice_model_records_path` artifact is supplied.
3. `workflow.requirements_to_pcb` must block when the explicit scenario lacks
   measurement envelopes.
4. `workflow.requirements_to_pcb` must block when the scenario points at a
   generic smoke deck instead of a deck with declared analyses and `.meas`
   evidence for every envelope.

## Fail-First Command

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests/testRequirementsWorkflowBlocksNarrativeSPICELogFromArtifactPaths \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests/testRequirementsWorkflowBlocksMissingSPICEModelRecordsArtifact \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests/testRequirementsWorkflowBlocksSPICEScenarioMissingEnvelopesFromArtifactPaths \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests/testRequirementsWorkflowBlocksGenericSmokeSPICEDeckFromArtifactPaths
```

## Red Result

`TEST FAILED`

- Generic smoke deck incorrectly returned workflow status `FAB_READY`.
- Missing model records reported only `SPICE_MODEL_REQUIRED`, not explicit
  missing model-record provenance.
- Narrative SPICE output reported missing/out-of-range measurements instead of
  explicit parse failure.
- Missing envelope coverage already blocked and remained covered.
