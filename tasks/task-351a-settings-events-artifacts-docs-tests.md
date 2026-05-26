# Task 351a — Settings Events Artifacts Docs Tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#plugin-settings-through-the-bus

## Behavior

WHEN this task is executed THE system SHALL add failing tests for
workspace-scoped settings schemas, event/artifact support, documentation, and
code-comment discipline.

## Context

Task 350b complete: sessions, subagents, MCP, domains, and verification are
bus-backed.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 19, 21, and 23:

19. Settings Schema Tests
21. Event/Artifact UI Tests
23. Documentation And Code-Comment Sweep

## Write to: MerlinTests/Unit/WorkspaceSettingsBusTests.swift

Prove:

- settings schemas register on the bus
- settings persist under
  `~/.merlin/workspaces/<workspace-id>/settings/<namespace>.toml`
- workspace settings override global defaults
- writing settings publishes `.settingsChanged`
- validation routes publish `.settingsValidation`
- secret fields are declared but not stored in plaintext by the workspace TOML
  store

## Write to: MerlinTests/Unit/WorkspaceEventArtifactTests.swift

Prove:

- handlers can publish progress and artifact events
- artifact metadata persists while full event history does not
- recent events are shared across sessions in the same workspace
- event filters by request ID, namespace prefix, and address work

## Write to: MerlinTests/Unit/MessageBusDocumentationSweepTests.swift

Add source/documentation assertions:

- Developer Manual documents `WorkspaceRuntime`, `WorkspaceMessageBus`,
  `WorkspaceMessageOrigin`, tool handler groups, MCP bus transport, domain
  capability routing, verification routing, settings schemas, event/artifact
  flow, and code-comment rules.
- User Guide and FEATURES mention the bus only where user-visible behavior
  exists.
- `spec.md` no longer says the message bus remains future-tense.
- Changed code comments follow the spec rules: public API doc comments where
  useful, no redundant WHAT-comments, and `// See: Developer Manual § "..."`
  only where the code is non-obvious enough to need a cross-reference.

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: BUILD FAILED or targeted documentation assertions fail.

## Commit

```bash
git add MerlinTests/Unit/WorkspaceSettingsBusTests.swift \
        MerlinTests/Unit/WorkspaceEventArtifactTests.swift \
        MerlinTests/Unit/MessageBusDocumentationSweepTests.swift \
        tasks/task-351a-settings-events-artifacts-docs-tests.md
git commit -m "Task 351a — settings events artifacts docs tests (failing)"
```
