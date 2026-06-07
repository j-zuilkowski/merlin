# Task 473b - Vendor BOM Evidence Gates

## Goal

Wire vendor/BOM evidence into the full workflow and runtime vendor package path
so Merlin cannot advance from placeholder BOMs or supplier prose.

## Implementation

- `FabricationReleaseEvidence` now carries explicit normalized BOM, vendor
  availability, cached datasheet evidence, and vendor order package paths.
- `FabricationReleaseGate` blocks `FAB_READY` when any required BOM/vendor
  artifact path is missing.
- `VendorAvailability` now carries optional unit price and source URL evidence;
  `VendorAvailabilityChecker` requires positive unit price evidence for
  orderable records.
- Added `BOMDatasheetEvidenceValidator` to require each BOM line to have locally
  cached datasheet evidence with a SHA-256 record.
- `ElectronicsEvidenceArtifactAdapter` now decodes datasheet evidence paths,
  validates them against the normalized BOM, and carries all BOM/vendor paths
  into workflow evidence.
- `kicad_prepare_vendor_order` now validates the normalized BOM, vendor
  availability, and cached datasheet evidence files before emitting a
  `vendor_order_package` artifact. The package records vendor, quantity,
  evidence paths, line count, total estimate, and `validated: true`.

## Focused Verification

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabReadyRequiresArtifactBackedBOMVendorDatasheetAndOrderEvidence \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingDatasheetCacheEvidenceBlocksBOMVendorFabrication \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresArtifactBackedBOMVendorEvidenceBeforeFabReady \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationRequiresRealBOMStockPriceAndDatasheetEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationEmitsPackageFromValidatedBOMStockPriceAndCachedDatasheets
```

Result: `TEST SUCCEEDED`, 5 tests, 0 failures.

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testCleanVerifierArtifactsReachFabReadyWithoutReleaseApproval \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testInvalidBOMVendorEvidenceBlocksFabrication \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingDatasheetCacheEvidenceBlocksBOMVendorFabrication \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresArtifactBackedBOMVendorEvidenceBeforeFabReady \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowCarriesSeparatedBoardDomainEvidenceThroughHandoff \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationRequiresRealBOMStockPriceAndDatasheetEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationEmitsPackageFromValidatedBOMStockPriceAndCachedDatasheets
```

Result: `TEST SUCCEEDED`, 14 tests, 0 failures.

## Remaining Scope

This completes the generic evidence gate and runtime vendor package path. It
does not run the full AmpDemo GUI demo, submit real orders, finish fabrication
packaging, verify GUI job-state consistency, or replace the current DRC routing
marker with native route geometry edits.
