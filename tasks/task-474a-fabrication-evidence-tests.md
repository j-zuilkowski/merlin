# Task 474a - Fabrication Evidence Tests

## Objective

Add fail-first coverage for the generic fabrication workflow gates so Merlin
cannot mark fabrication ready from declared paths, missing CAM/drawing/report
evidence, or incomplete `kicad_export_fab` artifacts.

## Fail-First Tests

Focused command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabricationEvidenceRequiresGerberDrillPlacementAndReport \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabricationEvidenceRequiresExistingOutputsAndPassingCAMReport \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingFabricationDrawingAndVerificationReportBlockFabReady \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadHandlersInvokeExecutableAndProduceEvidenceArtifacts
```

Expected red state before implementation:

- `testFabricationEvidenceRequiresGerberDrillPlacementAndReport` fails because
  assembly drawings are not yet required by the fabrication profile.
- `testFabricationEvidenceRequiresExistingOutputsAndPassingCAMReport` fails
  because fabrication validation does not yet check output file existence or
  CAM pass/fail status.
- `testMissingFabricationDrawingAndVerificationReportBlockFabReady` fails
  because drawing evidence is not yet part of the required fab evidence.
- `testKiCadHandlersInvokeExecutableAndProduceEvidenceArtifacts` fails because
  `kicad_export_fab` does not yet emit assembly drawing, fabrication evidence,
  or consolidated verification report artifacts.
