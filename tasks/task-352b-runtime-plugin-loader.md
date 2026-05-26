# Task 352b — Runtime Plugin Loader

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#runtime-plugin-transports

## Behavior

WHEN this task is executed THE system SHALL implement first-party Tier-1 plugin
loading on top of `WorkspaceMessageBus`.

## Context

Task 352a complete: plugin loader tests are failing.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence step 26.

## Add: Merlin/Plugins/RuntimePluginLoader.swift

Implement:

- plugin metadata model
- discovery from repo and installed first-party plugin paths
- Tier-1 in-process registration into the workspace bus
- Tier-2 metadata handoff to MCP/out-of-process transports
- disabled-plugin handling
- health/diagnostic bus events for load/unload failures

Do not expose a broad direct Swift plugin API. Plugins authenticate/configure
through metadata and speak over the workspace bus.

## Wire Into WorkspaceRuntime

Load built-in first-party plugins during runtime initialization. Keep failures
isolated to diagnostics; one plugin failure must not prevent the workspace from
opening.

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```

Expected: all tests pass, including task 352a.

## Commit

```bash
git add Merlin/Plugins/RuntimePluginLoader.swift \
        Merlin/Runtime/WorkspaceRuntime.swift \
        MerlinTests/Unit/RuntimePluginLoaderTests.swift \
        tasks/task-352b-runtime-plugin-loader.md
git commit -m "Task 352b — add first-party runtime plugin loader"
```
