# Task 410b — Datasheet Evidence Capture

## Goal

Add metadata-only datasheet evidence capture and wire it into component
selection decisions.

## Implementation

1. Add `DatasheetEvidence` schema/model support.
2. Record URL, provider ID, manufacturer, MPN, retrieval timestamp, cache policy,
   optional local path, and optional SHA-256.
3. Attach datasheet evidence references to `ComponentEvidence` and
   `PartSelectionDecision`.
4. Keep PDF download optional and provider-policy controlled.
5. Do not add RAG indexing in this stage.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DatasheetEvidenceCaptureTests \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected: tests pass.
