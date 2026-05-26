# Task 349b — Tool Router Bus Cutover

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#bus-backed-tool-calls

## Behavior

WHEN this task is executed THE system SHALL convert `ToolRouter` and all
built-in model-visible tools to the workspace bus with no production direct
closure routing path.

## Context

Task 349a complete: tool-router and built-in bus tests are failing.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 8, 9, and 10.

## Edit: Merlin/Engine/ToolRouter.swift

Replace production dispatch with:

1. resolve `ToolRoute` by tool name
2. run staging logic when appropriate
3. run `AuthGate` before side-effecting bus requests
4. build `WorkspaceMessageOrigin`
5. build `WorkspaceMessageRequest`
6. call `WorkspaceMessageBus.send`
7. convert `WorkspaceMessageResponse` to `ToolResult`

Remove production direct route dictionaries. `register(name:handler:)` may
remain only as a route-and-handler convenience that registers a bus handler.

## Edit: Merlin/App/ToolRegistration.swift

Convert built-in registrations into cohesive bus handler groups:

- `FileSystemMessageHandler`
- `ShellMessageHandler`
- `AppControlMessageHandler`
- `ToolDiscoveryMessageHandler`
- `XcodeMessageHandler`
- `UIAutomationMessageHandler`
- `VisionMessageHandler`
- `KnowledgeMessageHandler`
- `DisciplineMessageHandler`
- `AgentMessageHandler`

Handlers may call existing tool utility types. Old utility code is allowed;
old routing code is not.

## Edit: Merlin/App/AppState.swift

Construct `WorkspaceRuntime` and pass it to `ToolRouter`. Preserve streaming
`run_shell` log behavior by injecting a shell-event sink into the shell handler,
not by replacing the route with a direct closure.

## Edit: Merlin/Tools/ToolDefinitions.swift

Ensure every model-visible tool in `ToolDefinitions.all` has a registered route.
Do not reintroduce bare KiCad tools as built-ins; electronics is migrated later.

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```

Expected: all tests pass, including task 349a.

## Commit

```bash
git add Merlin/Engine/ToolRouter.swift \
        Merlin/App/ToolRegistration.swift \
        Merlin/App/AppState.swift \
        Merlin/Tools/ToolDefinitions.swift \
        MerlinTests/Unit/ToolRouterBusDispatchTests.swift \
        MerlinTests/Unit/BuiltInToolBusHandlerTests.swift \
        MerlinTests/Unit/DirectRouteEliminationTests.swift \
        tasks/task-349b-tool-router-bus-cutover.md
git commit -m "Task 349b — route built-in tools through workspace bus"
```
