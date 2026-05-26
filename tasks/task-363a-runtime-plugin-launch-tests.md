# Task 363a — Runtime plugin launch tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 363a is executed THE system SHALL add tests that workspace runtimes load enabled plugins.

GIVEN an active workspace runtime,
WHEN runtime plugin loading starts,
THEN enabled Tier-1 plugins SHALL register capabilities and publish health events.

## Red Test

- Assert `WorkspaceRuntime` exposes an explicit plugin loading entrypoint.
- Assert enabled electronics plugin metadata registers real routes in the workspace bus.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/WorkspaceRuntimePluginLaunchTests test
```

