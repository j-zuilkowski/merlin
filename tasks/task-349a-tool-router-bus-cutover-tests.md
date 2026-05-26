# Task 349a — Tool Router Bus Cutover Tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#bus-backed-tool-calls

## Behavior

WHEN this task is executed THE system SHALL add failing tests proving
`ToolRouter` and every built-in model-visible tool use the workspace bus.

## Context

Task 348b complete: workspace message contracts, runtime, and bus exist.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 7, 9, and 10:

7. ToolRouter Bus Dispatch Tests
9. Convert All Built-In Tool Handlers
10. Direct Route Elimination Gate

## Write to: MerlinTests/Unit/ToolRouterBusDispatchTests.swift

Add tests proving:

- `ToolRouter.dispatch` creates a `WorkspaceMessageRequest` and sends it through
  the active runtime's `WorkspaceMessageBus`.
- Unknown tool names return the existing user-facing unknown-tool error through
  a `ROUTE_NOT_FOUND` bus response.
- A `.failed` bus response retries once for ordinary handler failures.
- `.blocked`, `.unauthorized`, `.timedOut`, and `.cancelled` bus statuses
  become error `ToolResult`s with diagnostic text.
- `AuthGate` runs before side-effecting bus requests.
- Plan/ask-mode file mutations still stage through `StagingBuffer` before
  reaching the bus.
- Tool routes carry namespace, timeout, and required permission scope.

## Write to: MerlinTests/Unit/BuiltInToolBusHandlerTests.swift

Assert `registerAllTools(router:)` registers route metadata and bus handlers for
all model-visible built-ins in `ToolDefinitions.all`, including:

- file tools
- shell tools
- app control
- tool discovery
- Xcode tools
- UI/AX/CGEvent/screenshot/vision tools
- RAG tools
- discipline/generator tools
- `spawn_agent`

Tests may use route introspection and stub handlers; do not perform destructive
file writes, UI events, or real Xcode builds.

## Write to: MerlinTests/Unit/DirectRouteEliminationTests.swift

Add a source-scanning gate:

- `ToolRouter` may not contain production dictionaries named `handlers` or
  `mcpHandlers`.
- `ToolRouter.dispatchSingle` may not call a stored direct closure route.
- `register(name:handler:)`, if still present for tests or compatibility, must
  register a bus handler and route, not a parallel dispatch path.
- `MCPBridge` must register MCP tools as bus-backed routes.

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: BUILD FAILED with assertions or missing bus-router behavior.

## Commit

```bash
git add MerlinTests/Unit/ToolRouterBusDispatchTests.swift \
        MerlinTests/Unit/BuiltInToolBusHandlerTests.swift \
        MerlinTests/Unit/DirectRouteEliminationTests.swift \
        tasks/task-349a-tool-router-bus-cutover-tests.md
git commit -m "Task 349a — tool router bus cutover tests (failing)"
```
