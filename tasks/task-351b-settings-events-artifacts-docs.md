# Task 351b — Settings Events Artifacts Docs

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#plugin-settings-through-the-bus

## Behavior

WHEN this task is executed THE system SHALL implement workspace-scoped settings,
event/artifact support, and the required documentation/code-comment sweep.

## Context

Task 351a complete: settings/event/artifact/docs tests are failing.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 20, 22, 23, and 24.

## Add Runtime Stores

Implement:

- `WorkspaceSettingsStore`
- `WorkspaceArtifactStore`
- settings schema registration and validation dispatch
- artifact metadata persistence under the workspace state root
- event publication helpers for progress, diagnostics, artifacts, health,
  approvals, settings changes, and validation results

## Update UI/Event Access

Expose recent workspace events/artifacts through observable runtime state so the
sidebar/panels can consume them. Do not add a marketing screen. Keep UI surfaces
compact and consistent with existing Merlin panels.

## Documentation And Code-Comment Sweep

Update:

- `spec.md`
- `vision.md`
- `FEATURES.md`
- `Merlin/Docs/UserGuide.md`
- `Merlin/Docs/DeveloperManual.md`

Developer Manual must include sections for:

- `WorkspaceRuntime`
- `WorkspaceMessageBus`
- `WorkspaceMessageOrigin`
- tool handler groups
- MCP bus transport
- domain capability routing
- verification routing
- settings schemas
- event/artifact flow

Review changed comments against the spec's code-comment rules. Add
`// See: Developer Manual § "..."` only where useful. Update the Code Map for
each cross-reference.

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```

```bash
rg -n "message bus.*planned|WorkspaceMessageBus.*planned|direct ToolRouter closure dispatch|Status: not implemented" \
    spec.md vision.md FEATURES.md Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md
```

Expected: tests pass and stale-status sweep has no release-current hits.

## Commit

```bash
git add Merlin/Runtime \
        spec.md vision.md FEATURES.md Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md \
        MerlinTests/Unit/WorkspaceSettingsBusTests.swift \
        MerlinTests/Unit/WorkspaceEventArtifactTests.swift \
        MerlinTests/Unit/MessageBusDocumentationSweepTests.swift \
        tasks/task-351b-settings-events-artifacts-docs.md
git commit -m "Task 351b — workspace settings events artifacts and docs"
```
