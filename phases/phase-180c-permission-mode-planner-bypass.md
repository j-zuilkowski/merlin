# Phase 180c — Fix: PermissionModeTests planner-consumes-mock-response

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 180b complete: @MainActor CapturingAuthPresenter; pure tool-call chunks in place.

## Root Cause

`testAskModeShowsAuthPopupForFileWrite` (and `testAutoAcceptModeDoesNotShowAuthPopupForFileWrite`)
both pass `userMessage: "write a file"` to `engine.send(...)`.

`AgenticEngine.localClassification` inspects the message for planning keywords:

```swift
let planningKeywords = [
    "refactor", "migrate", "implement", "build", "create", "add", "update",
    "rewrite", "design", "change", "fix", "generate", "produce", "write", ...
]
if planningKeywords.contains(where: { lower.contains($0) }) {
    return ClassifierResult(needsPlanning: true, complexity: .standard, ...)
}
```

`"write a file"` contains the substring `"write"`, so `classification.needsPlanning = true`.
This causes the engine to invoke `PlannerEngine.decompose`, which calls:

```swift
let stream = try await provider.complete(request: request)
```

This is the **first** call to `PermissionModeCapturingProvider.complete`. The provider sets
`hasConsumedResponse = true` and returns `nextChunks` — the `write_file` tool-call chunks.

The planner's `parseSteps` fails to parse a tool-call JSON response as plan steps, returns `[]`,
and the engine continues without planning. But the tool-call response has been consumed.

Now the engine's main loop calls `provider.complete(request:)` a **second** time. Because
`hasConsumedResponse = true`, the provider returns only:

```swift
[CompletionChunk(delta: nil, finishReason: "stop")]
```

The stream has no tool call → `sawToolCall = false` → `guard sawToolCall, !assembled.isEmpty`
fails → tool dispatch is skipped entirely → `authGate.check` is never called →
`presenter.wasPrompted` stays `false` → test fails.

`testAutoAcceptModeDoesNotShowAuthPopupForFileWrite` passes trivially for the same reason:
the planner consumes the tool call, the engine gets a "stop" response, no auth check is
reached, `wasPrompted` stays `false`, and the assertion `XCTAssertFalse(wasPrompted)` passes.

## Fix

**Edit: `MerlinTests/Unit/PermissionModeTests.swift`**

Change the user message in both auth-popup tests from `"write a file"` to `"run tool"`.
`"run tool"` contains no planning keywords, so `classification.needsPlanning = false`,
the planner is never invoked, and the mock provider's tool-call response reaches the
engine's main loop on the first call.

### testAutoAcceptModeDoesNotShowAuthPopupForFileWrite

**Find**:
```swift
        for await _ in engine.send(userMessage: "write a file") {}

        XCTAssertFalse(presenter.wasPrompted,
                       "autoAccept mode must not prompt AuthGate for file write tools")
```

**Replace with**:
```swift
        for await _ in engine.send(userMessage: "run tool") {}

        XCTAssertFalse(presenter.wasPrompted,
                       "autoAccept mode must not prompt AuthGate for file write tools")
```

### testAskModeShowsAuthPopupForFileWrite

**Find**:
```swift
        for await _ in engine.send(userMessage: "write a file") {}

        XCTAssertTrue(presenter.wasPrompted,
                      "ask mode must show AuthGate popup for file write tools")
```

**Replace with**:
```swift
        for await _ in engine.send(userMessage: "run tool") {}

        XCTAssertTrue(presenter.wasPrompted,
                      "ask mode must show AuthGate popup for file write tools")
```

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'PermissionMode.*passed|PermissionMode.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; all PermissionModeTests pass including
`testAskModeShowsAuthPopupForFileWrite` and `testAutoAcceptModeDoesNotShowAuthPopupForFileWrite`.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/PermissionModeTests.swift \
        phases/phase-180c-permission-mode-planner-bypass.md
git commit -m "Phase 180c — Fix: change auth-popup test message to avoid planner keyword"
```
