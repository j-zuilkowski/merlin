# Task 413a — Real Catalog Provider Adapters Tests

## Goal

Add offline-verifiable tests for optional real catalog providers before enabling
network/API-backed component search.

## Failing Tests

Add focused tests proving:

1. Digi-Key adapter maps recorded fixture responses into `ComponentCandidate`
   evidence.
2. Mouser adapter maps recorded fixture responses into `ComponentCandidate`
   evidence.
3. Optional aggregator adapter maps recorded fixture responses into lifecycle and
   availability evidence.
4. Missing credentials disable live providers cleanly.
5. Live API tests are opt-in and never required for normal focused verification.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/RealCatalogProviderAdaptersTests
```

Expected: tests fail before Task 413b.
