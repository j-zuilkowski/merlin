# Task 348b — Workspace Message Bus Foundation

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#workspace-scoped-message-bus

## Behavior

WHEN this task is executed THE system SHALL implement the shared message
contracts, `WorkspaceRuntime`, and `WorkspaceMessageBus` needed by all later
bus-backed tooling.

## Context

Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 348a complete: foundation tests are failing.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 2, 4, and 6 from the bus plan:

2. Message Contract Implementation
4. WorkspaceRuntime Implementation
6. WorkspaceMessageBus Implementation

## Add: Merlin/Runtime/WorkspaceMessaging.swift

Implement shared contracts from `spec.md`:

- `WorkspaceMessageAddress`
- `WorkspacePermissionScope`
- `WorkspaceMessageOrigin`
- `WorkspaceMessagePayload`
- `WorkspaceDiagnostic`
- `WorkspaceArtifactRef`
- `WorkspaceMessageRequest`
- `WorkspaceMessageResponse`
- `WorkspaceMessageResponseStatus`
- `WorkspaceMessageEvent`
- `WorkspaceMessageEventKind`
- `WorkspaceMessageEventFilter`
- `WorkspaceCapability`
- `WorkspaceCapabilityKind`
- `WorkspaceSettingsSchema`
- `WorkspaceSettingsField`
- `WorkspaceSettingsFieldKind`
- `WorkspaceSettingsValue`
- `WorkspaceSettingsNamespace`
- `ToolRoute`
- `WorkspaceBootstrapMetadata`
- `WorkspaceHandlerContext`
- `WorkspaceMessageHandler`

Payloads must be canonical JSON data. Artifact references point to files or
artifact-store entries; binary data must not be embedded in bus messages.

## Add: Merlin/Runtime/WorkspaceMessageBus.swift

Implement actor-backed routing:

- register/unregister handlers by `WorkspaceMessageAddress`
- send requests with optional timeout
- cancel by request ID
- publish/subscribe event streams with filters
- bounded event ring buffer, default 1,000, clamped to a safe range
- capability and settings schema registration
- route-not-found, unauthorized, timeout, cancellation diagnostics

## Add: Merlin/Runtime/WorkspaceRuntime.swift

Implement a `@MainActor` runtime:

- one runtime per canonical workspace path
- persisted random UUID in `~/.merlin/workspaces/index.toml`
- state root under `~/.merlin/workspaces/<workspace-id>/`
- settings namespace paths under `settings/<namespace>.toml`
- owns a `WorkspaceMessageBus`
- owns workspace artifact and settings stores added in later tasks

Expose test-only initializers that accept a custom Merlin home directory.

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```

Expected: all tests pass, including task 348a.

## Commit

```bash
git add Merlin/Runtime/WorkspaceMessaging.swift \
        Merlin/Runtime/WorkspaceMessageBus.swift \
        Merlin/Runtime/WorkspaceRuntime.swift \
        MerlinTests/Unit/WorkspaceMessageContractTests.swift \
        MerlinTests/Unit/WorkspaceRuntimeTests.swift \
        MerlinTests/Unit/WorkspaceMessageBusTests.swift \
        tasks/task-348b-workspace-message-bus-foundation.md
git commit -m "Task 348b — workspace message bus foundation"
```
