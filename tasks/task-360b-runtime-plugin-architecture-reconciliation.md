# Task 360b — Runtime plugin architecture reconciliation

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 360b is executed THE system SHALL reconcile runtime plugin and electronics architecture documentation.

GIVEN documentation currently has mixed MCP and plugin-era language,
WHEN the reconciliation is complete,
THEN active-current docs SHALL state electronics is bus-backed through `plugins/electronics` and archived MCP text SHALL be historical only.

## Implementation

- Update `spec.md`, `vision.md`, `FEATURES.md`, `Merlin/Docs/UserGuide.md`, and `Merlin/Docs/DeveloperManual.md` as needed.
- Keep legacy MCP references only in historical/archive context.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsArchitectureReconciliationTests test
```

