# Task 201b — /compact Slash + Context-Length Recovery

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 201a complete: failing tests in ContextLengthRecoveryTests and CompactSlashCommandTests.

Fixes BUG-002 (/compact on-demand) and BUG-003 (context-length-exceeded treated as fatal).

---

## Edit: Merlin/Providers/ProviderError.swift

Add `isContextLengthExceeded` computed property after `isRetriable`:

```swift
/// True when the provider rejected the request because the prompt exceeded its context window.
/// These errors should trigger compaction + one retry rather than surfacing to the user.
var isContextLengthExceeded: Bool {
    guard case .httpError(let code, let body, _) = self, code == 400 else { return false }
    let lower = body.lowercased()
    return lower.contains("context_length_exceeded")
        || lower.contains("maximum context length")
        || lower.contains("input too long")
        || lower.contains("prompt is too long")
        || lower.contains("context window")
}
```

---

## Edit: TestHelpers/MockProvider.swift

Add two new initialiser paths and a `callCount` counter so tests can observe retry behaviour:

```swift
// Add to MockProvider stored properties:
private(set) var callCount: Int = 0
private let firstCallError: ProviderError?
private let allCallsError: ProviderError?

// Replace/extend existing init:
init(
    shouldFail: Bool = false,
    failFirstCallWith firstError: ProviderError? = nil,
    failAllCallsWith allError: ProviderError? = nil
) {
    self.firstCallError  = firstError
    self.allCallsError   = allError
    // shouldFail is equivalent to failAllCallsWith a generic 400
    let genericError: ProviderError? = shouldFail
        ? .httpError(statusCode: 400, body: "mock failure", providerID: "mock")
        : nil
    if allError == nil && shouldFail {
        self.allCallsError = genericError
    }
}

// At the top of the streaming/completion method, before any yield:
callCount += 1
if let err = allCallsError { throw err }
if callCount == 1, let err = firstCallError { throw err }
```

Adapt the exact implementation to however `MockProvider` currently throws — the important
invariant is that `callCount` increments before the error check so tests can verify retry count.

---

## Edit: Merlin/Engine/AgenticEngine.swift — context-length retry in `runLoop`

Locate the main `do { ... } catch { throw error }` block that wraps the provider call inside
`runLoop`. Add context-length detection before re-throwing. The retry is done by calling
`runLoop` once more (depth-limited to avoid infinite recursion). Use a local flag to track
whether a compaction-retry has already been attempted in this invocation.

Add a `private var contextLengthRetryCount: Int = 0` property on `AgenticEngine` (reset it
to 0 at the start of each top-level `send(userMessage:)` call, alongside `ceilingContinuationCount`).

In the catch block:

```swift
} catch let pe as ProviderError where pe.isContextLengthExceeded && contextLengthRetryCount == 0 {
    contextLengthRetryCount += 1
    continuation.yield(.systemNote(
        "[context too large — compacting and retrying…]"
    ))
    context.forceCompaction()
    // Re-run the same turn with the compacted context.
    try await runLoop(
        userMessage: userMessage,
        continuation: continuation,
        isContinuation: true,
        depth: depth
    )
} catch {
    TelemetryEmitter.shared.emit("engine.turn.error", data: [
        "turn": turn,
        "slot": workingSlot.rawValue,
        "provider_id": selectProvider(for: userMessage).id,
        "error_domain": (error as NSError).domain,
        "error_code": (error as NSError).code
    ])
    throw error
}
```

Reset `contextLengthRetryCount` to 0 in `send(userMessage:)` before starting the stream:

```swift
func send(userMessage: String) -> AsyncStream<AgentEvent> {
    contextLengthRetryCount = 0   // add this line
    ceilingContinuationCount = 0  // already exists
    // ... rest of existing implementation
```

---

## Edit: Merlin/Views/ChatView.swift — `/compact` slash command

In `handleSlashCommandIfNeeded(_:)`, extend the guard/match to also handle `compact`:

```swift
private func handleSlashCommandIfNeeded(_ message: String) -> Bool {
    guard message.hasPrefix("/") else { return false }
    let parts   = message.dropFirst().split(whereSeparator: \.isWhitespace)
    let command = parts.first.map(String.init)?.lowercased() ?? ""

    switch command {
    case "calibrate":
        // ... existing calibrate handling (unchanged) ...
        return true

    case "compact":
        appState.engine.contextManager.forceCompaction()
        // Surface a note in the conversation so the user sees it happened.
        appState.engine.emitSystemNote("[context compacted on demand]")
        return true   // consumed — do NOT send to the LLM

    default:
        return false
    }
}
```

`emitSystemNote` is a convenience that appends a `.systemNote` event to any in-flight
stream — if the engine is idle it can be a no-op (the note is cosmetic). If this helper
doesn't exist, add it to `AgenticEngine`:

```swift
/// Appends a system note to the active stream if a run is in progress; otherwise no-op.
func emitSystemNote(_ text: String) {
    activeContinuation?.yield(.systemNote(text))
}
```

Add `private var activeContinuation: AsyncStream<AgentEvent>.Continuation? = nil` as a stored
property on `AgenticEngine`, set it at the start of `send(userMessage:)` and clear it when the
stream finishes.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED. All ContextLengthRecoveryTests and CompactSlashCommandTests pass.
No regressions in prior test suites.

## Commit

```bash
git add Merlin/Providers/ProviderError.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Views/ChatView.swift \
        TestHelpers/MockProvider.swift
git commit -m "Task 201b — /compact slash + context-length auto-compact-retry (BUG-002, BUG-003)"
```

## Fixes

**BUG-002:** `/compact` in the chat bar now triggers `forceCompaction()` immediately and emits
a visible system note. The message is consumed by the slash handler and never forwarded to the
model.

**BUG-003:** `ProviderError.httpError(400, ...)` with a context-window body is now classified
as `isContextLengthExceeded`. The engine catches it before re-throwing, calls `forceCompaction()`,
and retries the turn once. A second failure on retry is surfaced as a normal error event. The
engine can no longer die silently from prompt-too-large during a long run.
