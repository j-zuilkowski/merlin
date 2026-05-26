# Task 363b — Runtime plugin launch wiring

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 363b is executed THE system SHALL wire runtime plugin loading into workspace startup.

GIVEN a workspace has enabled plugins,
WHEN the runtime loads plugins,
THEN the workspace bus SHALL contain those plugin capabilities and health events.

## Implementation

- Add workspace runtime plugin-loading API.
- Wire app/session startup to load active plugin roots.
- Keep load failures visible as diagnostics.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/WorkspaceRuntimePluginLaunchTests test
```

