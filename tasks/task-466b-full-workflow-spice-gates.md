# Task 466b - Full Workflow SPICE Evidence Gates

## Implementation

The structured electronics workflow path now carries SPICE model-record and
circuit-deck provenance from `evidence_artifacts` into
`ElectronicsEndToEndSPICEEvidence`.

`ElectronicsEndToEndHarness` now blocks SPICE advancement when artifact-backed
workflow evidence has:

- no local SPICE model-record artifact for required models;
- no parseable scalar measurements for declared envelopes;
- a missing circuit deck;
- a generic smoke deck that lacks declared analyses or `.meas` entries for the
  scenario envelopes.

`kicad_generate_spice_scenario` now uses the same circuit-deck validator before
copying a scenario deck, keeping the focused tool path and full workflow path on
the same deck standard.

## Focused Test Command

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests \
  -only-testing:MerlinTests/SPICEOptimizationTests \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationRejectsProjectOnlyGenericDeckRequest \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingEnvelopesAndModelRefs \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingOrUnusableModelEvidence \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationProducesExplicitRunnableDeckArtifact \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOutOfEnvelopeMeasurementsAndKeepsLog
```

## Result

`TEST SUCCEEDED`

- Tests: 22
- Failures: 0

No full AmpDemo GUI demo was run.
