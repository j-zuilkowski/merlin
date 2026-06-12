# Task 463a - SPICE Envelope Gate Tests

## Goal

Add focused regression coverage proving Merlin cannot mark SPICE complete just
because ngspice exits successfully.

## Requirements

1. Parse real ngspice scalar measurements even when a value is followed by
   trailing range metadata.
2. Block `kicad_run_spice` when supplied measurement envelopes are missing or
   out of range.
3. Preserve the SPICE log artifact on envelope failures.
4. Add a guarded AmpDemo slice that runs real ngspice and proves the current
   low-voltage smoke deck does not satisfy the 25 W output envelope.

## Evidence

Focused tests:

```sh
RUN_AMPDEMO_SPICE_SLICE=1 xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/SPICEOptimizationTests/testNgspiceMeasurementParserReadsScalarMeasurements \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOutOfEnvelopeMeasurementsAndKeepsLog \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOnNgspiceErrorsAndPreservesRepairDiagnostics \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testAmpDemoSPICESliceBlocksWhen25WEnvelopeFails
```

Initial run passed the non-live tests but skipped the live AmpDemo test because
Xcode did not propagate the environment variable into the test process.

