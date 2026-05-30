# Task 381a — Electronics plugin signing tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#workspace-message-bus--runtime-plugin-architecture
- Prior failure: `WorkspaceRuntimePluginLaunchTests/testWorkspaceRuntimeLoadsEnabledElectronicsPluginFromRoot`

## Behavior

WHEN Merlin builds the first-party electronics runtime plugin THE repo-copied `plugins/electronics/libMerlinElectronicsPlugin.dylib` SHALL be loadable by the runtime test process.

GIVEN `plugins/electronics/plugin.json` points at the repo-copied dylib,
WHEN `WorkspaceRuntime` loads that manifest from a plugin root,
THEN dynamic loading SHALL succeed and electronics routes SHALL be registered.

## Red Tests

- Add or tighten a unit test that asserts the copied
  `plugins/electronics/libMerlinElectronicsPlugin.dylib` exists after a normal
  build and has a valid code signature acceptable to `dlopen` in the test
  process.
- Keep `WorkspaceRuntimePluginLaunchTests/testWorkspaceRuntimeLoadsEnabledElectronicsPluginFromRoot`
  as the end-to-end runtime load assertion.
- Assert the copy script declares an output path so Xcode dependency analysis can
  reason about the generated dylib.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/WorkspaceRuntimePluginLaunchTests test
```

Expected red state: the runtime launch test fails with a code-signature/dlopen
error until task 381b signs or otherwise resolves the copied dylib.
