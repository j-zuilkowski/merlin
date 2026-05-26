# Task 348a — Workspace Message Bus Foundation Tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#workspace-scoped-message-bus

## Behavior

WHEN this task is executed THE system SHALL add failing tests for the shared
workspace message contracts, `WorkspaceRuntime`, and `WorkspaceMessageBus`.

## Context

Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 1, 3, and 5 from the bus plan:

1. Message Contract Tests
3. WorkspaceRuntime Tests
5. WorkspaceMessageBus Tests

The production implementation lands in task 348b.

## Write to: MerlinTests/Unit/WorkspaceMessageContractTests.swift

Add deterministic tests proving:

- `WorkspaceMessageAddress(namespace: "builtin.files", capability: "read_file")`
  is hashable, codable, and renders as `builtin.files/read_file`.
- `WorkspaceMessagePayload` stores canonical JSON bytes, decodes codable payloads,
  and never embeds binary artifact data.
- `WorkspaceMessageOrigin` includes workspace ID, session ID, subagent ID,
  worktree ID, subagent depth, permission scope, and active domain IDs.
- `WorkspacePermissionScope` allows expected escalation only:
  - `readOnly` allows only read-only.
  - `worktreeWrite` allows read-only + worktree writes.
  - `workspaceWrite` allows read-only + worktree/workspace writes.
  - `externalSideEffect` allows read-only + external side effects only.
  - `userApprovedIrreversible` allows all scopes.
- Missing route diagnostics use code `ROUTE_NOT_FOUND`.
- Unauthorized diagnostics use code `UNAUTHORIZED_SCOPE`.

## Write to: MerlinTests/Unit/WorkspaceRuntimeTests.swift

Use a temporary home/workspace root and assert:

- A new workspace path receives a persisted random UUID.
- Reopening the same canonical path resolves the same UUID.
- A different path receives a different UUID.
- Workspace-owned state lives under
  `~/.merlin/workspaces/<workspace-id>/`.
- Settings namespaces resolve to
  `~/.merlin/workspaces/<workspace-id>/settings/<namespace>.toml`.
- The runtime default event capacity is 1,000 and clamps unsafe values.

## Write to: MerlinTests/Unit/WorkspaceMessageBusTests.swift

Add an in-process test handler and prove:

- Registered handlers receive requests and return `.ok` payloads.
- Unregistered addresses return `.failed` with `ROUTE_NOT_FOUND`.
- A handler that receives insufficient origin scope returns `.unauthorized`
  with `UNAUTHORIZED_SCOPE`.
- Request timeouts return `.timedOut` with `REQUEST_TIMED_OUT`.
- `cancel(requestID:)` returns/publishes cancellation state.
- Subscribers receive matching `.progress`, `.artifactProduced`,
  `.healthChanged`, `.diagnostic`, `.approvalRequired`, `.settingsChanged`,
  and `.settingsValidation` events.
- The in-memory event ring buffer keeps only the configured recent events.

Keep tests local and deterministic. Do not launch providers, MCP servers, Xcode,
or external processes.

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: BUILD FAILED with errors naming missing workspace message bus symbols.

## Commit

```bash
git add MerlinTests/Unit/WorkspaceMessageContractTests.swift \
        MerlinTests/Unit/WorkspaceRuntimeTests.swift \
        MerlinTests/Unit/WorkspaceMessageBusTests.swift \
        tasks/task-348a-workspace-message-bus-foundation-tests.md
git commit -m "Task 348a — workspace message bus foundation tests (failing)"
```
