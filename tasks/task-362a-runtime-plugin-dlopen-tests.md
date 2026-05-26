# Task 362a — Runtime plugin dlopen tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 362a is executed THE system SHALL add tests for real Tier-1 dynamic plugin loading.

GIVEN a Tier-1 plugin manifest names a dynamic library and factory symbols,
WHEN the plugin loader runs,
THEN Merlin SHALL load the library and dispatch requests through the plugin handler instead of generic closure placeholders.

## Red Test

- Build a tiny fixture dynamic library during the test.
- Assert `RuntimePluginLoader` calls the fixture handler and returns its response.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/RuntimePluginDynamicLoadingTests test
```

