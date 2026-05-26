# Task 360a — Runtime plugin architecture reconciliation tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 360a is executed THE system SHALL add tests that catch contradictory runtime plugin and electronics status documentation.

GIVEN the runtime plugin and electronics architecture has been promoted,
WHEN architecture and user-facing documentation are scanned,
THEN the docs SHALL describe one active architecture and mark legacy MCP wording as historical only.

## Red Test

- Add tests that fail while `spec.md` still describes `merlin-kicad-mcp` as an active current integration layer.
- Assert current docs identify `plugins/electronics`, workspace bus routing, and historical-only legacy MCP references.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsArchitectureReconciliationTests test
```

