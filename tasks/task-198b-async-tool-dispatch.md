# Task 198b — Async Tool Dispatch Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 198a complete: failing tests in place.

## Changes to: Merlin/Engine/AgenticEngine.swift

### 1. Extract dispatchRegularCalls() (the new internal method the tests call)

Replace the existing `for call in regularCalls { ... }` loop body (lines ~969–1044) with a
call to a new internal method:

```swift
await dispatchRegularCalls(
    regularCalls,
    turn: turn,
    loopCount: loopCount,
    writtenFilePaths: &writtenFilePaths,
    continuation: continuation
)
```

### 2. Add the new method

```swift
/// Dispatches all regular (non-spawn_agent) tool calls for one loop iteration.
///
/// Three-task approach:
///   1. Sequential pre-hooks  — preserves hook side-effect ordering
///   2. Batch parallel dispatch — passes all allowed calls to ToolRouter at once
///   3. Sequential context updates — preserves OpenAI wire-format message ordering
func dispatchRegularCalls(
    _ calls: [ToolCall],
    turn: Int,
    loopCount: Int,
    writtenFilePaths: inout [String],
    continuation: AsyncStream<AgentEvent>.Continuation
) async {
    guard !calls.isEmpty else { return }

    // MARK: Task 1 — sequential pre-hooks
    struct PrehookOutcome {
        let call: ToolCall
        let denied: ToolResult?
        let writtenPath: String?
    }

    var prehookOutcomes: [PrehookOutcome] = []
    for call in calls {
        let input = inputDictionary(from: call.function.arguments)
        let decision = await hookEngine.runPreToolUse(toolName: call.function.name, input: input)
        switch decision {
        case .deny(let reason):
            let denied = ToolResult(
                toolCallId: call.id,
                content: "Blocked by hook: \(reason)",
                isError: true
            )
            prehookOutcomes.append(PrehookOutcome(call: call, denied: denied, writtenPath: nil))
        case .allow:
            let path: String? = call.function.name == "write_file"
                ? inputDictionary(from: call.function.arguments)["path"]
                : nil
            prehookOutcomes.append(PrehookOutcome(call: call, denied: nil, writtenPath: path))
        }
    }

    // MARK: Task 2 — batch parallel dispatch
    let allowedCalls = prehookOutcomes.compactMap { $0.denied == nil ? $0.call : nil }
    let batchStart = Date()
    let batchResults: [ToolResult]
    if allowedCalls.isEmpty {
        batchResults = []
    } else {
        for call in allowedCalls {
            TelemetryEmitter.shared.emit("engine.tool.dispatched", data: [
                "turn": turn,
                "tool_name": call.function.name,
                "loop": loopCount
            ])
        }
        batchResults = await toolRouter.dispatch(allowedCalls)
    }
    let batchMs = Date().timeIntervalSince(batchStart) * 1000

    // MARK: Task 3 — sequential context updates (original call order)
    var batchIndex = 0
    for outcome in prehookOutcomes {
        let result: ToolResult
        if let denied = outcome.denied {
            result = denied
        } else {
            result = batchResults[batchIndex]
            batchIndex += 1
            if result.isError {
                TelemetryEmitter.shared.emit("engine.tool.error", durationMs: batchMs, data: [
                    "turn": turn,
                    "tool_name": outcome.call.function.name,
                    "loop": loopCount,
                    "error_domain": "tool_dispatch"
                ])
            } else {
                TelemetryEmitter.shared.emit("engine.tool.complete", durationMs: batchMs, data: [
                    "turn": turn,
                    "tool_name": outcome.call.function.name,
                    "loop": loopCount,
                    "duration_ms": batchMs,
                    "result_bytes": result.content.utf8.count
                ])
            }
        }

        if let path = outcome.writtenPath {
            writtenFilePaths.append(path)
        }

        continuation.yield(.toolCallResult(result))
        context.append(Message(
            role: .tool,
            content: .text(result.content),
            toolCallId: result.toolCallId,
            timestamp: Date()
        ))
        emitCompactionNoteIfNeeded()

        if let note = await hookEngine.runPostToolUse(
            toolName: outcome.call.function.name,
            result: result.content
        ) {
            continuation.yield(.systemNote(note))
            context.append(Message(role: .system, content: .text(note), timestamp: Date()))
            emitCompactionNoteIfNeeded()
        }
    }
}
```

### 3. Update the call site in runLoop()

Find the block (around line 969) that previously read:
```swift
for call in regularCalls {
    let input = inputDictionary(from: call.function.arguments)
    let hookDecision = await hookEngine.runPreToolUse(...)
    ...
    let results = await toolRouter.dispatch([call])
    ...
}
```

Replace the entire block with:
```swift
await dispatchRegularCalls(
    regularCalls,
    turn: turn,
    loopCount: loopCount,
    writtenFilePaths: &writtenFilePaths,
    continuation: continuation
)
```

Note: `context` is the `ContextManager` local to `runLoop`. `dispatchRegularCalls` uses
`self.context` (the engine's `contextManager` property via a local alias set up at the top
of `runLoop`). Verify that the reference resolves correctly — if `context` is a local alias
rather than `self.contextManager`, pass it as an explicit parameter instead.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all 198a tests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Task 198b — Async batch tool dispatch"
```
