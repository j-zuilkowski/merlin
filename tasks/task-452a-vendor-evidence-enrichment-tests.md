# Task 452a: Vendor Evidence Enrichment Tests

## Goal

Prove component selection can use corroborating provider evidence without
weakening the required manufacturer, MPN, package, ratings, datasheet, and
provenance gate.

## Scope

1. Same MPN evidence from multiple providers must hydrate into one candidate
   before validation.
2. Nexar GraphQL fixture evidence must route through the Nexar adapter when
   requested.
3. Deterministic ranking must prefer exact electrical/rating matches over
   over-specified but otherwise valid candidates.
4. Missing evidence must remain blocked.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testSamePartProviderEvidenceHydratesBeforeValidation \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testDeterministicRankingPrefersExactRatingsOverOverspecifiedValidCandidates \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testNexarProviderFixtureUsesNexarAdapterForSelectionEvidence
```

Expected: `TEST SUCCEEDED`.
