# Phase 97 — Wire HookEngine into Main AgenticEngine Loop

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 96 complete: AgentRegistry.registerBuiltins() called at launch.

`HookEngine` fires only for subagent tool calls (in `SubagentEngine` and
`WorkerSubagentEngine`). The parent `AgenticEngine.runLoop` dispatches tool calls
directly through `toolRouter.dispatch(regularCalls)` with no hook involvement.
Architecture specifies four hook events: `PreToolUse`, `PostToolUse`,
`UserPromptSubmit`, and `Stop`. None fire for the parent agent today.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1. Add a stored HookEngine property

Add a stored property near the top of `AgenticEngine` (alongside `permissionMode`):

```swift
    private var hookEngine: HookEngine {
        HookEngine(hooks: AppSettings.shared.hooks)
    }
```

(This creates a fresh engine reflecting the current hooks each time; acceptable since
hooks are read at call time anyway. If `HookEngine` is expensive to init, store it as
a `var hookEngine = HookEngine(hooks: [])` and update it when hooks change.)

### 2. UserPromptSubmit hook — before user message is processed

At the start of `runLoop`, before the line:
```swift
context.append(Message(role: .user, content: .text(effectiveMessage), timestamp: Date()))
```

Add:
```swift
        if let augmented = await hookEngine.runUserPromptSubmit(prompt: effectiveMessage) {
            continuation.yield(.systemNote(augmented))
        }
```

### 3. PreToolUse + PostToolUse hooks — around each tool call

Replace the tool dispatch block. Currently:

```swift
            let results = await toolRouter.dispatch(regularCalls)
            for (_, result) in zip(regularCalls, results) {
                continuation.yield(.toolCallResult(result))
                context.append(Message(
                    role: .tool,
                    content: .text(result.content),
                    toolCallId: result.toolCallId,
                    timestamp: Date()
                ))
            }
```

Replace with hook-aware dispatch:

```swift
            for call in regularCalls {
                let input = (try? JSONSerialization.jsonObject(
                    with: Data(call.function.arguments.utf8)
                ) as? [String: Any]) ?? [:]

                let hookDecision = await hookEngine.runPreToolUse(
                    toolName: call.function.name, input: input
                )
                switch hookDecision {
                case .deny(let reason):
                    let denied = ToolResult(
                        toolCallId: call.id,
                        content: "Blocked by hook: \(reason)"
                    )
                    continuation.yield(.toolCallResult(denied))
                    context.append(Message(
                        role: .tool,
                        content: .text(denied.content),
                        toolCallId: denied.toolCallId,
                        timestamp: Date()
                    ))
                    continue
                case .allow:
                    break
                }

                let results = await toolRouter.dispatch([call])
                guard let result = results.first else { continue }
                continuation.yield(.toolCallResult(result))
                context.append(Message(
                    role: .tool,
                    content: .text(result.content),
                    toolCallId: result.toolCallId,
                    timestamp: Date()
                ))

                if let note = await hookEngine.runPostToolUse(
                    toolName: call.function.name, result: result.content
                ) {
                    continuation.yield(.systemNote(note))
                    context.append(Message(role: .system, content: .text(note), timestamp: Date()))
                }
            }
```

### 4. Stop hook — after a turn completes (no tool calls in response)

The `while true` loop breaks when `sawToolCall == false`. Just before the `break`:

```swift
            guard sawToolCall, !assembled.isEmpty else {
                let shouldContinue = await hookEngine.runStop()
                if shouldContinue {
                    // re-inject a continuation trigger
                    context.append(Message(role: .user,
                        content: .text("[Hook: continue]"), timestamp: Date()))
                    continue
                }
                break
            }
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 97 — Wire HookEngine (PreToolUse/PostToolUse/UserPromptSubmit/Stop) into main AgenticEngine loop"
```
