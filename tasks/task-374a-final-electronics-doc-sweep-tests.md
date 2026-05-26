# Task 374a — Final electronics documentation sweep tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 374a is executed THE system SHALL add final drift tests for electronics completion documentation.

GIVEN all runtime and electronics gaps are closed,
WHEN docs are scanned,
THEN no active-current document SHALL overstate completion or describe archived MCP as current.

## Red Test

- Assert docs mention evidence-gated completion.
- Assert stale active MCP phrases are absent.
- Assert runtime plugin status matches implemented loader behavior.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests test
```

