# Task 465a - SPICE Model Evidence And Repair Boundary Tests

## Goal

Prevent SPICE workflow advancement when Merlin lacks model-availability
evidence or when a repair loop would change electrical parameters without
declared engineering bounds.

## Requirements

1. Scenario generation must block when no SPICE model records artifact is
   supplied.
2. Scenario generation must block when required model records are absent or not
   legally usable.
3. Valid scenario generation must return the model records artifact as workflow
   evidence.
4. SPICE repair must block when measurements already satisfy the declared
   envelopes.
5. SPICE repair must block when generated patches reference parameters without
   declared min/max bounds.
6. The AmpDemo focused SPICE slice must run an explicit representative 25 W
   low-voltage output-stage scenario, not a generic smoke deck.

## Focused Test Command

```sh
touch /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-spice-slice
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/SPICEOptimizationTests/testSPICEScenarioRequiresCircuitPathAnalysesAndMeasurementEnvelopes \
  -only-testing:MerlinTests/SPICEOptimizationTests/testNgspiceMeasurementParserReadsScalarMeasurements \
  -only-testing:MerlinTests/SPICEOptimizationTests/testModelResolverBlocksRequiredUnapprovedGenericSubstitute \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationRejectsProjectOnlyGenericDeckRequest \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingEnvelopesAndModelRefs \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingOrUnusableModelEvidence \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationProducesExplicitRunnableDeckArtifact \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOutOfEnvelopeMeasurementsAndKeepsLog \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testSPICERepairActionPlansMeasurementRepairAndBlocksUnsupportedLog \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testAmpDemoSPICESliceRunsExplicit25WOutputStageScenario
rm -f /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-spice-slice
```

## Result

`TEST SUCCEEDED`

- Tests: 10
- Failures: 0

