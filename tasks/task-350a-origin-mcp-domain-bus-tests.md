# Task 350a — Origin MCP Domain Bus Tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#subagents-and-the-bus

## Behavior

WHEN this task is executed THE system SHALL add failing tests for session/shared
workspace origins, MCP bus transport routes, domain capabilities, and
verification routing.

## Context

Task 349b complete: built-in tool dispatch is bus-backed.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 11, 13, 15, and 17:

11. Subagent Origin Tests
13. MCP Bus Adapter Tests
15. Domain Capability Tests
17. Verification Bus Tests

## Write to: MerlinTests/Unit/WorkspaceRuntimeSessionTests.swift

Prove:

- `WorkspaceCoordinator` creates one `WorkspaceRuntime` per project path.
- Multiple sessions for the same project share the same runtime and bus.
- `LiveSession` passes the runtime to `AppState` and `ToolRouter`.
- Active domain IDs are included in every tool origin.

## Write to: MerlinTests/Unit/SubagentBusOriginTests.swift

Prove:

- Parent session tool calls carry parent session origin.
- Explorer subagent calls are `readOnly`.
- Default subagent calls include `subagentID` and parent session ID.
- Worker subagent calls include `worktreeID`, `subagentID`, and use
  `worktreeWrite` for file mutations.
- Worker writes are rejected if they attempt direct workspace writes outside
  the worktree.

## Write to: MerlinTests/Unit/MCPBusTransportTests.swift

Prove:

- `MCPBridge` registers each MCP tool as a `ToolRoute` under `mcp.<server>`.
- Dispatching an MCP tool goes through `WorkspaceMessageBus`.
- Domain-scoped MCP filtering remains intact.
- `MCPBridge.stop` unregisters bus routes and tool definitions.

## Write to: MerlinTests/Unit/DomainCapabilityBusTests.swift

Prove:

- `DomainPlugin` exposes `WorkspaceCapability` metadata and optional
  `WorkspaceSettingsSchema`.
- `SoftwareDomain` and `ElectronicsDomain` provide capability metadata.
- `MCPDomainAdapter` converts manifest tool/verification/settings metadata to
  bus capabilities.

## Write to: MerlinTests/Unit/VerificationBusTests.swift

Prove:

- Stage-1/domain verification can dispatch a verification capability through
  the bus.
- Shell-based `VerificationBackend` remains available behind a bus handler.
- Missing verification route returns `ROUTE_NOT_FOUND`, not a silent pass.

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: BUILD FAILED with missing origin/MCP/domain bus behavior.

## Commit

```bash
git add MerlinTests/Unit/WorkspaceRuntimeSessionTests.swift \
        MerlinTests/Unit/SubagentBusOriginTests.swift \
        MerlinTests/Unit/MCPBusTransportTests.swift \
        MerlinTests/Unit/DomainCapabilityBusTests.swift \
        MerlinTests/Unit/VerificationBusTests.swift \
        tasks/task-350a-origin-mcp-domain-bus-tests.md
git commit -m "Task 350a — origin MCP domain bus tests (failing)"
```
