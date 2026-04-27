# Phase 17b — AgenticEngine Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 17a complete: AgenticEngineTests.swift written. All engine components exist.

---

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

    // Weak reference — injected by AppState after construction
    weak var sessionStore: SessionStore?

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
4. Accumulate tool_calls from stream deltas using [Int: (id,name,args)] dictionary:
   var assembled: [Int: (id: String, name: String, args: String)] = [:]
   for each ToolCallDelta in chunk.delta?.toolCalls:
       var entry = assembled[delta.index] ?? (id: delta.id ?? "", name: "", args: "")
       if let n = delta.function?.name, !n.isEmpty { entry.name = n }
       if let id = delta.id, !id.isEmpty { entry.id = id }
       entry.args += delta.function?.arguments ?? ""
       assembled[delta.index] = entry
5. If assembled is non-empty (tool_calls present):
   a. Convert assembled dict to [ToolCall] sorted by index
   b. Yield .toolCallStarted for each
   c. router.dispatch(calls) → results
   d. Yield .toolCallResult for each
   e. let prevCompactionCount = contextManager.compactionCount
   f. Append results to contextManager as tool messages
   g. If contextManager.compactionCount != prevCompactionCount →
         yield .systemNote("[context compacted — old tool results summarised]")
   h. Go to step 2
6. Done — save session
```

## @MainActor + AsyncStream concurrency

`AgenticEngine` is `@MainActor`. `send` returns an `AsyncStream<AgentEvent>` — the stream
continuation is created on the main actor and the internal Task stays on the main actor:

```swift
func send(userMessage: String) -> AsyncStream<AgentEvent> {
    AsyncStream { continuation in
        Task { @MainActor in
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

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/AgenticEngineTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'AgenticEngineTests' passed` with 4 tests.

Also verify zero warnings with strict concurrency:
```bash
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|warning:|error:'
```

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 17b — AgenticEngine implementation (4 tests passing)"
```
