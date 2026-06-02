# Task 449a: Live Vendor Evidence Selection Tests

## Goal

Add failing tests proving live vendor catalog evidence is normalized into
selection-ready component candidates before `kicad_select_components` can pick
parts.

## Scope

1. Verify Mouser and Digi-Key adapters preserve manufacturer part number,
   manufacturer, package/case, datasheet URL, lifecycle, stock summary, and
   extracted electrical ratings.
2. Verify resistor-like circuit intent such as `RPRE1` and `RBIAS1` generates
   resistor/value/rating search terms instead of symbol-name queries.
3. Verify evidence extracted from provider records hydrates otherwise-empty
   candidate fields before package/datasheet/rating validation.
4. Verify incompatible package/rating constraints block selection instead of
   allowing a false positive.
5. Verify multiple valid candidates remain blocked as ambiguous unless one
   candidate is uniquely better by explicit evidence and constraints.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testMouserAdapterExtractsPackageAndRatingsFromDescription \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testDigiKeyAdapterPreservesDatasheetPackageStockAndRatings \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testResistorRoleQueriesUseStructuredElectricalIntent \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testCandidateEvidenceHydrationPreventsFalsePackageDatasheetBlock \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testExplicitPackageConstraintRejectsIncompatibleCatalogCandidate \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testMultipleValidCandidatesSelectsUniqueBestRankedCandidate
```

Expected: tests fail before implementation and pass after task 449b.
