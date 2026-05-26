# Task 352a — Runtime Plugin Loader Tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#runtime-plugin-transports

## Behavior

WHEN this task is executed THE system SHALL add failing tests for first-party
Tier-1 plugin discovery, trust policy, metadata loading, and bus registration.

## Context

Task 351b complete: bus foundation, settings, events, artifacts, and
documentation are current.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence step 26:

26. Then Plugin Loader

## Write to: MerlinTests/Unit/RuntimePluginLoaderTests.swift

Prove:

- Merlin discovers first-party plugin bundles under `plugins/*` or an installed
  first-party plugin directory.
- Plugin metadata declares ID, display name, version, trust tier, domain IDs,
  capabilities, settings schema, and required bus routes.
- Tier-1 plugins register in-process handlers on the workspace bus.
- Tier-2/out-of-process plugins are represented by MCP/transport metadata, not
  loaded in-process.
- Disabled plugins do not register routes.
- Plugin load errors publish `.diagnostic`/`.healthChanged` events and do not
  crash the workspace.

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: BUILD FAILED with missing runtime plugin loader symbols.

## Commit

```bash
git add MerlinTests/Unit/RuntimePluginLoaderTests.swift \
        tasks/task-352a-runtime-plugin-loader-tests.md
git commit -m "Task 352a — runtime plugin loader tests (failing)"
```
