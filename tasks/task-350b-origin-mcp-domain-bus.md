# Task 350b — Origin MCP Domain Bus

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#subagents-and-the-bus

## Behavior

WHEN this task is executed THE system SHALL wire shared workspace runtimes,
subagent origins, MCP transport routes, domain capabilities, and verification
routing through `WorkspaceMessageBus`.

## Context

Task 350a complete: origin/MCP/domain bus tests are failing.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 12, 14, 16, and 18.

## Edit: Merlin/Sessions/*

`WorkspaceCoordinator` owns runtimes keyed by canonical project path.
`SessionManager`, `LiveSession`, and `AppState` receive the same runtime for
all sessions in the same workspace.

## Edit: Merlin/Engine/AgenticEngine.swift

When dispatching parent and subagent tools, configure `ToolRouter` origin
metadata with:

- session ID
- subagent ID
- worker worktree ID
- subagent depth
- active domain IDs
- correct permission scope

## Edit: Merlin/MCP/MCPBridge.swift

Replace MCP direct handler registration with `MCPMessageTransport` bus routes.
Preserve:

- `mcp:<server>:<tool>` model-visible names
- active-domain filtering
- `DomainRegistry` registration from MCP manifests
- `stop(toolRouter:)` cleanup

## Edit: Merlin/MCP/DomainPlugin.swift and domains

Add capability and optional settings-schema metadata to `DomainPlugin`.
Populate built-in software/electronics domains. Convert MCP manifests into
capabilities where available.

## Add: Merlin/Runtime/VerificationMessageHandler.swift

Provide bus-backed domain verification. Existing `VerificationBackend`
implementations remain useful command providers behind the handler, but
verification has a bus route.

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```

Expected: all tests pass, including task 350a.

## Commit

```bash
git add Merlin/Sessions/WorkspaceCoordinator.swift \
        Merlin/Sessions/SessionManager.swift \
        Merlin/Sessions/LiveSession.swift \
        Merlin/App/AppState.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/MCP/MCPBridge.swift \
        Merlin/MCP/DomainPlugin.swift \
        Merlin/MCP/SoftwareDomain.swift \
        Merlin/Runtime/VerificationMessageHandler.swift \
        MerlinTests/Unit/WorkspaceRuntimeSessionTests.swift \
        MerlinTests/Unit/SubagentBusOriginTests.swift \
        MerlinTests/Unit/MCPBusTransportTests.swift \
        MerlinTests/Unit/DomainCapabilityBusTests.swift \
        MerlinTests/Unit/VerificationBusTests.swift \
        tasks/task-350b-origin-mcp-domain-bus.md
git commit -m "Task 350b — share workspace bus across sessions and transports"
```
