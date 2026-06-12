# Task 419a - Runtime Catalog Provider Selection Tests

## Goal

Add focused tests proving `kicad_select_components` can use configured catalog
provider evidence directly, without a prebuilt `catalog_candidates_path`.

## Failing Tests

Add focused tests proving:

1. Runtime selection accepts recorded provider fixture paths keyed by provider
   ID.
2. Digi-Key, Mouser, and aggregator fixture responses are converted into
   `ComponentCandidate` rows.
3. Provider-derived candidates are matched to concrete Circuit IR refdes.
4. Matrix metadata records provider source and TTL/cache policy.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected: tests fail before Task 419b.
