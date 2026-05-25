# Task 180b — Fix: PermissionModeTests auth popup — @MainActor on CapturingAuthPresenter + pure tool-call chunks

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 180a complete: PermissionModeTests failure documented.

## Fix (two-part)

### Part 1 — Edit: `TestHelpers/NullAuthPresenter.swift`

Add `@MainActor` to `CapturingAuthPresenter` to match the `@MainActor AuthPresenter`
protocol requirement. This ensures the `requestDecision` method and `wasPrompted`
property access are MainActor-isolated, matching how `AuthGate.check` calls them.

**Find**:
```swift
final class CapturingAuthPresenter: AuthPresenter {
    let response: AuthDecision
    var wasPrompted = false

    init(response: AuthDecision) { self.response = response }

    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        wasPrompted = true
        return response
    }
}
```

**Replace with**:
```swift
@MainActor
final class CapturingAuthPresenter: AuthPresenter {
    let response: AuthDecision
    var wasPrompted = false

    init(response: AuthDecision) { self.response = response }

    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        wasPrompted = true
        return response
    }
}
```

### Part 2 — Edit: `MerlinTests/Unit/PermissionModeTests.swift`

Simplify `makeEngineWithFileWriteResponse` to use ONLY tool-call chunks (not mixed with
text). Mixing a `"tool_calls"` finish reason with a subsequent `"stop"` finish reason in
the same stream can confuse the engine's capturedFinishReason. The second `complete` call
(for the engine's second loop iteration) will naturally return just `stop`.

**Find** (~line 117):
```swift
        provider.nextChunks = MockLLMResponse.toolCall(
            id: "tc1",
            name: "write_file",
            args: #"{"path":"/tmp/test.txt","content":"hello"}"#
        ).chunks + MockLLMResponse.text("done").chunks
```

**Replace with**:
```swift
        provider.nextChunks = MockLLMResponse.toolCall(
            id: "tc1",
            name: "write_file",
            args: #"{"path":"/tmp/test.txt","content":"hello"}"#
        ).chunks
```

Also use UUID-based auth memory paths to prevent cross-test contamination:

**Find** (~line 103-104):
```swift
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-perm-test.json"),
```

**Replace with**:
```swift
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-perm-\(UUID().uuidString).json"),
```

**Find** (~line 144-145):
```swift
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-perm-test2.json"),
```

**Replace with**:
```swift
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-perm2-\(UUID().uuidString).json"),
```

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'PermissionMode.*passed|PermissionMode.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; all PermissionModeTests pass (including
`testAskModeShowsAuthPopupForFileWrite`).

If still failing after Part 1 + Part 2, investigate further by adding a temporary
`print("requestDecision called")` inside `CapturingAuthPresenter.requestDecision`
and checking the test output.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add TestHelpers/NullAuthPresenter.swift \
        MerlinTests/Unit/PermissionModeTests.swift \
        tasks/task-180b-permission-mode-fix.md
git commit -m "Task 180b — Fix: @MainActor CapturingAuthPresenter; pure tool-call chunks in PermissionModeTests"
```
