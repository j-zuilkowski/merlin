# Task 362b — Runtime plugin dlopen implementation

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 362b is executed THE system SHALL implement real Tier-1 dynamic plugin loading.

GIVEN a plugin provides a supported dynamic entrypoint,
WHEN Merlin loads it,
THEN requests SHALL be routed to the plugin's exported handler function.

## Implementation

- Extend plugin metadata with dynamic library and symbol fields.
- Use `dlopen`/`dlsym` for Tier-1 dynamic plugins.
- Remove generic successful placeholder handler registration.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/RuntimePluginDynamicLoadingTests test
```

