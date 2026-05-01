# Phase diag-03b — Engine Telemetry Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-03a complete: failing tests in place.

Instrument `AgenticEngine` to emit telemetry events covering the turn lifecycle and every tool dispatch.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1. Add `setRegistryForTesting` test helper (after `setMemoryBackend`)

Find:
```swift
    /// Inject the active memory backend.
    func setMemoryBackend(_ backend: any MemoryBackendPlugin) async {
        memoryBackend = backend
```

Add **after** the closing brace of `setMemoryBackend`:
```swift
    /// Wire a single provider as pro/flash/vision for unit tests.
    func setRegistryForTesting(provider: any LLMProvider) {
        self.proProvider = provider
        self.flashProvider = provider
        self.visionProvider = provider
    }
```

---

### 2. Instrument `send(userMessage:)` — emit `engine.turn.start` and `engine.provider.selected`

Locate the beginning of `send(userMessage:)`. Find the line that calls `selectProvider(for:)` (inside the body of the returned `AsyncStream`). It looks approximately like:

```swift
        let provider = selectProvider(for: userMessage)
```

Replace with:
```swift
        let turnNumber = turn
        TelemetryEmitter.shared.emit("engine.turn.start", data: [
            "turn":           TelemetryValue.int(turnNumber),
            "slot":           TelemetryValue.string(selectSlot(for: userMessage).rawValue),
            "message_length": TelemetryValue.int(userMessage.count)
        ])
        let provider = selectProvider(for: userMessage)
        TelemetryEmitter.shared.emit("engine.provider.selected", data: [
            "turn":        TelemetryValue.int(turnNumber),
            "slot":        TelemetryValue.string(selectSlot(for: userMessage).rawValue),
            "provider_id": TelemetryValue.string(provider.id)
        ])
```

---

### 3. Instrument `runLoop` — emit `engine.turn.complete` and `engine.turn.error`

At the **end** of `runLoop`, just before the function returns normally, add:

```swift
        let turnMs = Date().timeIntervalSince(loopStart) * 1000
        TelemetryEmitter.shared.emit("engine.turn.complete", durationMs: turnMs, data: [
            "turn":              TelemetryValue.int(turn),
            "slot":              TelemetryValue.string(workingSlot.rawValue),
            "provider_id":       TelemetryValue.string(selectProvider(for: userMessage).id),
            "total_duration_ms": TelemetryValue.double(turnMs),
            "tool_call_count":   TelemetryValue.int(totalToolCallCount),
            "loop_count":        TelemetryValue.int(loopCount)
        ])
```

Add `let loopStart = Date()` at the very beginning of `runLoop` (after the `let context = ...` line), and add tracking vars `var totalToolCallCount = 0` and `var loopCount = 0`. Increment `loopCount` at the top of each streaming iteration and `totalToolCallCount` for each tool call batch.

Wrap the top-level `try` block in `runLoop` in a `do/catch` that emits `engine.turn.error` on failure:

```swift
        do {
            // ... existing loop body ...
        } catch {
            TelemetryEmitter.shared.emit("engine.turn.error", data: [
                "turn":         TelemetryValue.int(turn),
                "slot":         TelemetryValue.string(workingSlot.rawValue),
                "provider_id":  TelemetryValue.string(selectProvider(for: userMessage).id),
                "error_domain": TelemetryValue.string((error as NSError).domain),
                "error_code":   TelemetryValue.int((error as NSError).code)
            ])
            throw error
        }
```

---

### 4. Instrument tool dispatch — emit `engine.tool.dispatched`, `engine.tool.complete`, `engine.tool.error`

In the `for call in regularCalls` loop, find the line:

```swift
                let results = await toolRouter.dispatch([call])
```

Replace the entire block that dispatches a single tool and yields its result with:

```swift
                TelemetryEmitter.shared.emit("engine.tool.dispatched", data: [
                    "turn":      TelemetryValue.int(turn),
                    "tool_name": TelemetryValue.string(call.function.name),
                    "loop":      TelemetryValue.int(loopCount)
                ])
                let toolStart = Date()
                do {
                    let results = await toolRouter.dispatch([call])
                    guard let result = results.first else { continue }
                    let toolMs = Date().timeIntervalSince(toolStart) * 1000
                    TelemetryEmitter.shared.emit("engine.tool.complete", durationMs: toolMs, data: [
                        "turn":         TelemetryValue.int(turn),
                        "tool_name":    TelemetryValue.string(call.function.name),
                        "loop":         TelemetryValue.int(loopCount),
                        "duration_ms":  TelemetryValue.double(toolMs),
                        "result_bytes": TelemetryValue.int(result.content.utf8.count)
                    ])
                    continuation.yield(.toolCallResult(result))
                    context.append(Message(
                        role: .tool,
                        content: .text(result.content),
                        toolCallId: result.toolCallId,
                        timestamp: Date()
                    ))
                    emitCompactionNoteIfNeeded()

                    if let note = await hookEngine.runPostToolUse(
                        toolName: call.function.name,
                        result: result.content
                    ) {
                        continuation.yield(.systemNote(note))
                        context.append(Message(role: .system, content: .text(note), timestamp: Date()))
                        emitCompactionNoteIfNeeded()
                    }
                } catch {
                    let toolMs = Date().timeIntervalSince(toolStart) * 1000
                    TelemetryEmitter.shared.emit("engine.tool.error", durationMs: toolMs, data: [
                        "turn":         TelemetryValue.int(turn),
                        "tool_name":    TelemetryValue.string(call.function.name),
                        "loop":         TelemetryValue.int(loopCount),
                        "error_domain": TelemetryValue.string((error as NSError).domain),
                        "error_code":   TelemetryValue.int((error as NSError).code)
                    ])
                    // Surface error as a tool result so the model can recover
                    let errResult = ToolResult(
                        toolCallId: call.id,
                        content: "Tool error: \(error.localizedDescription)",
                        isError: true
                    )
                    continuation.yield(.toolCallResult(errResult))
                    context.append(Message(
                        role: .tool,
                        content: .text(errResult.content),
                        toolCallId: errResult.toolCallId,
                        timestamp: Date()
                    ))
                }
```

Note: remove the old `continuation.yield(.toolCallResult(result))` + `context.append(...)` + `hookEngine.runPostToolUse` block that follows `toolRouter.dispatch` — it is now inside the `do` block above.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'EngineTelemetry|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all EngineTelemetryTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Phase diag-03b — Engine telemetry instrumentation"
```
