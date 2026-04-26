# Phase 17b — AgenticEngine Implementation

Context: HANDOFF.md. All engine components exist. Make phase-17a tests pass.

## Write to: Merlin/Engine/AgenticEngine.swift

```swift
import Foundation

enum AgentEvent {
    case text(String)           // streamed LLM text
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case systemNote(String)     // e.g. "[context compacted]"
    case error(Error)
}

@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    private let toolRouter: ToolRouter
    private let thinkingDetector = ThinkingModeDetector.self
    private let proProvider: any LLMProvider
    private let flashProvider: any LLMProvider
    private let visionProvider: LMStudioProvider

    init(proProvider: any LLMProvider,
         flashProvider: any LLMProvider,
         visionProvider: LMStudioProvider,
         toolRouter: ToolRouter,
         contextManager: ContextManager)

    // Registers a tool handler (delegates to ToolRouter)
    func registerTool(_ name: String, handler: @escaping (String) async throws -> String)

    // Sends a user message, returns an AsyncStream of AgentEvents
    // Loops internally until provider returns no tool_calls
    func send(userMessage: String) -> AsyncStream<AgentEvent>
}
```

Provider selection in `send`:
- Vision task signals (message contains "screenshot", "screen", "vision", "ui", "click", "button") → `visionProvider`
- Mechanical signals (matches ThinkingModeDetector OFF words) → `flashProvider`
- Otherwise → `proProvider` with thinking config from `ThinkingModeDetector.config(for:)`

Loop structure:
```
1. Append user message to contextManager
2. Select provider
3. Stream completion → yield .text events
4. Accumulate tool_calls from stream (reassemble from deltas by index, same
   pattern as phase-24 live test: [Int: (id,name,args)] dictionary)
5. If tool_calls present:
   a. Yield .toolCallStarted for each
   b. router.dispatch(calls) → results
   c. Yield .toolCallResult for each
   d. let prevCompactionCount = contextManager.compactionCount
   e. Append results to contextManager
   f. If contextManager.compactionCount != prevCompactionCount →
         yield .systemNote("[context compacted — old tool results summarised]")
   g. Go to step 2
6. Done — save session (see Session save wiring below)
```

## @MainActor + AsyncStream concurrency

`AgenticEngine` is `@MainActor`. `send` returns an `AsyncStream<AgentEvent>` — the stream
continuation is created on the main actor and stored as `nonisolated(unsafe)` so it can
be called from the internal `Task`. The internal Task is launched with `Task { @MainActor in ... }`
so it remains on the main actor while still being asynchronous:

```swift
func send(userMessage: String) -> AsyncStream<AgentEvent> {
    AsyncStream { continuation in
        Task { @MainActor in
            // all await calls here run on main actor via cooperative scheduling
            // provider.complete() suspends and resumes on main actor — safe
            do {
                try await self.runLoop(userMessage: userMessage, continuation: continuation)
                continuation.finish()
            } catch {
                continuation.yield(.error(error))
                continuation.finish()
            }
        }
    }
}
```

## Session save wiring

After each full turn (no more tool_calls in response), call:
```swift
if let session = sessionStore?.activeSession {
    var updated = session
    updated.messages = contextManager.messages
    updated.updatedAt = Date()
    try? sessionStore?.save(updated)
}
```
`AgenticEngine` holds a weak reference to `SessionStore` (injected in `AppState.init`).

## Acceptance
- [ ] `swift test --filter AgenticEngineTests` — all 4 pass
- [ ] `swift build` — zero errors, zero warnings with SWIFT_STRICT_CONCURRENCY=complete
