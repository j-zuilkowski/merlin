# Task 408a — Component Catalog Contracts Tests

## Goal

Lock the electronics-plugin data contracts for evidence-backed component
selection before wiring runtime behavior.

## Failing Tests

Add focused tests proving:

1. `ComponentSearchRequest`, `ComponentCandidate`, `ComponentEvidence`,
   `DatasheetEvidence`, `FootprintCandidate`, `PartSelectionDecision`, and
   `ComponentMatrix` round-trip through plugin-owned schemas.
2. A `ComponentCandidate` without manufacturer, MPN, package/rating evidence, or
   provider provenance is rejected.
3. A deterministic fixture catalog provider can return candidates without
   network access or API keys.
4. KiCad/local CAD catalog providers expose symbol and footprint evidence as
   provider evidence, not as model claims.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests
```

Expected: tests fail before Task 408b.
