# Task 473a - Vendor BOM Evidence Tests

## Goal

Add fail-first coverage proving BOM/vendor workflow advancement requires
artifact-backed BOM, stock/price, cached datasheet, and vendor package evidence
instead of placeholder BOMs or narrative supplier claims.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN BOM/vendor workflow gates are evaluated THE electronics workflow SHALL
require artifact-backed BOM, stock/price, cached datasheet, and vendor package
evidence before fabrication or release can advance.

## Tests Added

- `FabBOMReleaseTests.testFabReadyRequiresArtifactBackedBOMVendorDatasheetAndOrderEvidence`
  verifies `FAB_READY` blocks when BOM/vendor/datasheet/order package paths are
  absent, even if boolean validation summaries are otherwise valid.
- `ElectronicsEvidenceArtifactAdapterTests.testMissingDatasheetCacheEvidenceBlocksBOMVendorFabrication`
  verifies evidence-adapter output blocks fabrication when cached datasheet
  evidence is missing.
- `ElectronicsEndToEndHarnessTests.testWorkflowRequiresArtifactBackedBOMVendorEvidenceBeforeFabReady`
  verifies the full workflow path blocks `FAB_READY` when upstream schematic,
  PCB, and SPICE gates are satisfied but BOM/vendor evidence paths are missing.
- `ElectronicsToolFailureEvidenceTests.testVendorOrderPreparationRequiresRealBOMStockPriceAndDatasheetEvidence`
  verifies runtime vendor order preparation blocks when only a normalized BOM
  path is supplied.
- `ElectronicsToolFailureEvidenceTests.testVendorOrderPreparationEmitsPackageFromValidatedBOMStockPriceAndCachedDatasheets`
  verifies runtime vendor order preparation emits a real package artifact only
  from valid BOM, stock/price, and cached datasheet evidence.

## Fail-First Evidence

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabReadyRequiresArtifactBackedBOMVendorDatasheetAndOrderEvidence \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingDatasheetCacheEvidenceBlocksBOMVendorFabrication \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationRequiresRealBOMStockPriceAndDatasheetEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationEmitsPackageFromValidatedBOMStockPriceAndCachedDatasheets
```

Result: `TEST FAILED` at compile time. `FabricationReleaseEvidence` had no
`normalizedBOMPath`, `vendorAvailabilityPath`, `datasheetEvidencePath`, or
`vendorOrderPackagePath` fields, proving the workflow could not distinguish
artifact-backed BOM/vendor evidence from validation summaries.
