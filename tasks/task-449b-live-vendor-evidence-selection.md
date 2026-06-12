# Task 449b: Live Vendor Evidence Selection

## Goal

Normalize live catalog provider evidence and use deterministic component
selection so Merlin cannot advance with weak, ambiguous, or incompatible parts.

## Scope

1. Preserve Mouser and Digi-Key evidence fields during adapter normalization:
   MPN, manufacturer, package/case, datasheet URL, stock, lifecycle, ratings,
   and provenance.
2. Build live catalog queries from structured `ComponentSearchRequest` intent:
   refdes family, role, value, package, rating, footprint, and pin constraints.
3. Hydrate candidate package, ratings, and datasheet fields from provider
   `ComponentEvidence.extractedParameters` before validation.
4. Reject candidates that violate required package, mounting, capacitance,
   voltage, current, or power constraints.
5. Select exactly one candidate only when evidence and ranking make it uniquely
   best; otherwise return a truthful `blocked` or `ambiguous` decision with the
   unresolved constraint.

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

Expected: `TEST SUCCEEDED`.
