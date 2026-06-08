# Task 410a — Datasheet Evidence Capture Tests

## Goal

Preserve datasheet metadata as evidence artifacts before full PDF/RAG indexing
exists.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN component datasheet evidence is captured THE electronics workflow SHALL preserve metadata artifacts before release-grade selected decisions advance.

## Failing Tests

Add focused tests proving:

1. Selected components carry datasheet evidence references.
2. Datasheet metadata includes manufacturer, MPN, URL or local path, provider ID,
   retrieval timestamp, and cache policy.
3. Local PDF artifacts record SHA-256 when stored.
4. Missing datasheet evidence prevents release-grade `selected` decisions when
   the component class requires a datasheet.
5. RAG chunk/page fields are optional and absent by default.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DatasheetEvidenceCaptureTests
```

Expected: tests fail before Task 410b.
