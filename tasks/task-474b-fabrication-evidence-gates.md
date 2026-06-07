# Task 474b - Fabrication Evidence Gates

## Objective

Wire fabrication output evidence into Merlin's generic electronics workflow so
fabrication readiness requires real Gerber, Excellon drill, CAM, pick-and-place,
assembly drawing, and consolidated verification artifacts.

## Implementation

- `FabricatorProfile.jlcPCBTwoLayer` now requires:
  - `gerber_archive`
  - `excellon_drill`
  - `pick_and_place`
  - `assembly_drawing`
  - `fabrication_report`
- `FabricationEvidenceValidator` now rejects:
  - missing required output kinds;
  - declared output paths that do not exist or are empty;
  - empty output directories;
  - CAM reports that do not decode to `pass` or `ok` status.
- `kicad_export_fab` now invokes KiCad CLI exports for:
  - Gerbers;
  - Excellon drills;
  - position/pick-and-place data;
  - assembly drawing SVG output.
- `kicad_export_fab` now blocks if structural artifact checks fail and emits:
  - `cam_report`
  - `fabrication_evidence`
  - `verification_report`
  along with the exported Gerber/drill/PnP/drawing artifacts.
- Clean fabrication fixture helpers now include assembly drawing evidence.

## Verification

Fail-first command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabricationEvidenceRequiresGerberDrillPlacementAndReport \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabricationEvidenceRequiresExistingOutputsAndPassingCAMReport \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingFabricationDrawingAndVerificationReportBlockFabReady \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadHandlersInvokeExecutableAndProduceEvidenceArtifacts
```

Red result before implementation: `TEST FAILED`, 4 tests executed, 7 expected
assertion failures in the new fabrication checks.

Green command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabricationEvidenceRequiresGerberDrillPlacementAndReport \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabricationEvidenceRequiresExistingOutputsAndPassingCAMReport \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingFabricationDrawingAndVerificationReportBlockFabReady \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadHandlersInvokeExecutableAndProduceEvidenceArtifacts
```

Result: `TEST SUCCEEDED`, 4 tests, 0 failures.

Broader focused command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testCleanVerifierArtifactsReachFabReadyWithoutReleaseApproval \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingFabricationDrawingAndVerificationReportBlockFabReady \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testFailedDRCRunKeepsReportArtifactForHarnessRepairEvidence \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadHandlersInvokeExecutableAndProduceEvidenceArtifacts
```

Result: `TEST SUCCEEDED`, 12 tests, 0 failures.

## Notes

The full AmpDemo GUI demo was not run. A broader artifact-path runtime test with
the stale mixed-domain fixture still blocks upstream on design-intent and
schematic verification gates; this task intentionally did not weaken those gates.
