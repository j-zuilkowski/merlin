# Task 464a - Explicit SPICE Scenario Tests

## Goal

Prevent Merlin from generating or advancing SPICE workflow evidence from a
generic project-only smoke deck.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN SPICE scenario generation is requested THE electronics workflow SHALL require explicit scenario evidence, measurement envelopes, and model references.

## Requirements

1. `kicad_generate_spice_scenario` must block when only `project_path` is
   supplied.
2. Scenario generation must require CircuitIR with a SPICE verification
   scenario.
3. Scenario generation must require explicit `SPICESimulationScenario` data.
4. Scenarios without measurement envelopes or model references must block.
5. Valid explicit scenarios must produce a runnable deck artifact without
   inserting Merlin's old generic smoke deck.
6. AmpDemo live SPICE slice must go through scenario generation before
   invoking ngspice.

## Focused Test Command

```sh
touch /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-spice-slice
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/SPICEOptimizationTests/testSPICEScenarioRequiresCircuitPathAnalysesAndMeasurementEnvelopes \
  -only-testing:MerlinTests/SPICEOptimizationTests/testNgspiceMeasurementParserReadsScalarMeasurements \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationRejectsProjectOnlyGenericDeckRequest \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingEnvelopesAndModelRefs \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationProducesExplicitRunnableDeckArtifact \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOutOfEnvelopeMeasurementsAndKeepsLog \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testAmpDemoSPICESliceBlocksWhen25WEnvelopeFails
rm -f /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-spice-slice
```
