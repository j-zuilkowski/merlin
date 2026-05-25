# Task 180a — PermissionModeTests: auth popup not triggered in ask mode (failing — pre-existing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 179b complete: ThreadAutomationEngine loop interval fix.

## Problem

`PermissionModeTests.testAskModeShowsAuthPopupForFileWrite` fails because
`presenter.wasPrompted` is false after the engine processes a `write_file` tool call
in `.ask` permission mode.

Expected: `authGate.check("write_file", ...)` calls `presenter.requestDecision(...)`,
setting `wasPrompted = true`.

The `PermissionModeCapturingProvider.nextChunks` is set to:
```swift
MockLLMResponse.toolCall(id: "tc1", name: "write_file", ...).chunks +
MockLLMResponse.text("done").chunks
```

This yields 4 chunks in one stream:
1. ToolCall delta (finishReason: nil)
2. `finishReason: "tool_calls"`
3. Text "done" (finishReason: nil)
4. `finishReason: "stop"`

The engine reads ALL 4 chunks before exiting the stream loop (the loop does not break on
finishReason). After the loop, `sawToolCall = true` and `capturedFinishReason = "stop"`.
The guard `guard sawToolCall, !assembled.isEmpty` passes and the tool call is dispatched.

HOWEVER: mixing text chunks AFTER tool_call chunks in the same stream causes the engine
to accumulate `fullText = "done"` alongside the tool call. This combined response may
cause unexpected behaviour in certain engine paths.

**Most likely root cause** (to be confirmed by Codex): the `CapturingAuthPresenter` lacks
`@MainActor` annotation, causing its `requestDecision` method to be dispatched to a
non-MainActor thread where the `wasPrompted = true` write does not propagate to the
test's assertion context under strict concurrency.

**Alternative causes to investigate**:
1. The mixed toolCall+text stream causes the engine to reach a code path where
   `toolRouter.permissionMode` is not yet `.ask` when dispatch happens
2. The `AuthGate.presenter` weak reference becomes nil (unlikely — test frame holds strong ref)
3. `CapturingAuthPresenter` needs to be `@MainActor`

## Failing test

`MerlinTests/Unit/PermissionModeTests.testAskModeShowsAuthPopupForFileWrite`

## Existing test file

`MerlinTests/Unit/PermissionModeTests.swift` — already committed.

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'PermissionMode.*failed|BUILD' | head -10
```

Expected: `testAskModeShowsAuthPopupForFileWrite` fails.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add tasks/task-180a-permission-mode-tests.md
git commit -m "Task 180a — PermissionModeTests auth-popup failure documented"
```
