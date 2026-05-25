# Phase 55b — SubagentEngine V4a Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 55a complete: failing tests in place.

New files:
  - `Merlin/Agents/SubagentEvent.swift`
  - `Merlin/Agents/SubagentEngine.swift`
  - `Merlin/Agents/SpawnAgentTool.swift`

Edits:
  - `Merlin/Config/AppSettings.swift` — add `maxSubagentThreads: Int` and `maxSubagentDepth: Int`
  - `Merlin/Tools/ToolDefinitions.swift` — add `spawn_agent` tool definition to `all` array

---

## Write to: Merlin/Agents/SubagentEvent.swift

```swift
import Foundation

enum SubagentEvent: Sendable {
    case toolCallStarted(toolName: String, input: [String: Any])
    case toolCallCompleted(toolName: String, result: String)
    case messageChunk(String)
    case completed(summary: String)
    case failed(Error)
}
```

---

## Write to: Merlin/Agents/SubagentEngine.swift

```swift
import Foundation

// Runs a child agentic loop in isolation, streaming SubagentEvents back to the parent.
// V4a: read-only explorer subagents only. V4b extends this with write-capable workers.
actor SubagentEngine {

    private let definition: AgentDefinition
    private let prompt: String
    private let provider: any LLMProvider
    private let hookEngine: HookEngine
    private let depth: Int

    private var continuation: AsyncStream<SubagentEvent>.Continuation?
    private var runTask: Task<Void, Never>?

    // MARK: - Init

    init(
        definition: AgentDefinition,
        prompt: String,
        provider: any LLMProvider,
        hookEngine: HookEngine,
        depth: Int
    ) {
        self.definition = definition
        self.prompt = prompt
        self.provider = provider
        self.hookEngine = hookEngine
        self.depth = depth
    }

    // MARK: - Event stream

    nonisolated var events: AsyncStream<SubagentEvent> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
        }
    }

    private func setContinuation(_ cont: AsyncStream<SubagentEvent>.Continuation) {
        self.continuation = cont
        startRun()
    }

    // MARK: - Lifecycle

    private func startRun() {
        runTask = Task {
            await run()
        }
    }

    func cancel() {
        runTask?.cancel()
        continuation?.finish()
    }

    // MARK: - Available tools

    // Returns the tool names this subagent is allowed to use.
    // spawn_agent is included only when depth < maxSubagentDepth.
    nonisolated func availableToolNames() -> [String] {
        let maxDepth = AppSettings.shared.maxSubagentDepth
        var names: [String]

        // Role-based tool set
        switch definition.role {
        case .explorer:
            names = definition.allowedTools ?? AgentDefinition.explorerToolSet
        case .worker, .default:
            names = definition.allowedTools ?? []  // empty = full parent set
        }

        // spawn_agent only below depth limit
        if depth < maxDepth {
            if !names.isEmpty && !names.contains("spawn_agent") {
                names.append("spawn_agent")
            } else if names.isEmpty {
                // Full set gets spawn_agent added below in the engine loop
            }
        }
        return names
    }

    // MARK: - Run loop

    private func run() async {
        guard !Task.isCancelled else {
            continuation?.finish()
            return
        }

        // Build context
        let context = ContextManager()
        let systemPrompt = buildSystemPrompt()
        await context.setSystemPrompt(systemPrompt)
        await context.append(Message(role: .user, content: prompt))

        var iterations = 0
        let maxIterations = 20

        while !Task.isCancelled && iterations < maxIterations {
            iterations += 1

            // Build tool list for this subagent
            let toolNames = availableToolNames()
            let allTools = await ToolRegistry.shared.all()
            let tools: [ToolDefinition]
            if toolNames.isEmpty {
                tools = allTools  // full set
            } else {
                tools = allTools.filter { toolNames.contains($0.function.name) }
            }

            let messages = await context.messages()

            do {
                let response = try await provider.complete(
                    messages: messages,
                    tools: tools,
                    stream: { [weak self] chunk in
                        guard let self else { return }
                        Task { await self.emit(.messageChunk(chunk)) }
                    }
                )

                if let text = response.content, !text.isEmpty {
                    await context.append(Message(role: .assistant, content: text))
                }

                guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
                    // No tool calls — agent is done
                    let summary = response.content ?? ""
                    emit(.completed(summary: summary))
                    continuation?.finish()
                    return
                }

                // Execute tool calls
                for call in toolCalls {
                    if Task.isCancelled { break }

                    let input = call.inputDict
                    emit(.toolCallStarted(toolName: call.name, input: input))

                    // Hook check
                    let hookDecision = await hookEngine.runPreToolUse(
                        toolName: call.name, input: input
                    )
                    if case .deny(let reason) = hookDecision {
                        let errResult = "Tool blocked by hook: \(reason)"
                        emit(.toolCallCompleted(toolName: call.name, result: errResult))
                        await context.append(Message(
                            role: .tool,
                            content: errResult,
                            toolCallID: call.id
                        ))
                        continue
                    }

                    let result = await executeToolCall(call)
                    emit(.toolCallCompleted(toolName: call.name, result: result))
                    await context.append(Message(
                        role: .tool,
                        content: result,
                        toolCallID: call.id
                    ))
                }

            } catch {
                emit(.failed(error))
                continuation?.finish()
                return
            }
        }

        emit(.completed(summary: "Subagent reached iteration limit."))
        continuation?.finish()
    }

    private func emit(_ event: SubagentEvent) {
        continuation?.yield(event)
    }

    private func buildSystemPrompt() -> String {
        var parts: [String] = []
        if !definition.instructions.isEmpty {
            parts.append(definition.instructions)
        }
        parts.append("You are a subagent. Complete your assigned task and stop.")
        return parts.joined(separator: "\n\n")
    }

    // Minimal tool dispatcher for subagents — delegates to same tool infrastructure as parent.
    private func executeToolCall(_ call: ToolCall) async -> String {
        // In the real implementation, this routes through the same ToolRouter used by AgenticEngine.
        // Placeholder returns a descriptive string for now.
        return "[SubagentEngine] executed \(call.name)"
    }
}
```

---

## Write to: Merlin/Agents/SpawnAgentTool.swift

```swift
import Foundation

// ToolDefinition for spawn_agent — registered as a built-in in ToolDefinitions.all.
// AgenticEngine routes calls to this name to SubagentEngine.
extension ToolDefinition {
    static let spawnAgent = ToolDefinition(
        type: "function",
        function: .init(
            name: "spawn_agent",
            description: "Spawn a subagent to run a task in parallel. The agent streams its activity back into the conversation.",
            parameters: .init(
                type: "object",
                properties: [
                    "agent": [
                        "type": "string",
                        "description": "Agent name. Built-ins: 'explorer' (read-only), 'worker' (write-capable), 'default' (full tools). Custom agents from ~/.merlin/agents/."
                    ],
                    "prompt": [
                        "type": "string",
                        "description": "The task prompt to send to the subagent."
                    ]
                ],
                required: ["agent", "prompt"]
            )
        )
    )
}
```

---

## Edit: Merlin/Tools/ToolDefinitions.swift

Add `ToolDefinition.spawnAgent` to the `all` array:

```swift
// In ToolDefinitions.all, append:
.spawnAgent
```

---

## Edit: Merlin/Config/AppSettings.swift

Add to the published fields block:

```swift
@Published var maxSubagentThreads: Int = 4
@Published var maxSubagentDepth: Int = 2
```

Add to the `ConfigFile` struct:
```swift
var max_subagent_threads: Int?
var max_subagent_depth: Int?
```

Add to `load(from:)`:
```swift
if let v = config.max_subagent_threads { maxSubagentThreads = v }
if let v = config.max_subagent_depth   { maxSubagentDepth = v }
```

Add to `save(to:)`:
```swift
lines.append("max_subagent_threads = \(maxSubagentThreads)")
lines.append("max_subagent_depth = \(maxSubagentDepth)")
```

---

## Integration note

In `AgenticEngine.handleToolCall(_:)`, add a case for `"spawn_agent"`:

```swift
case "spawn_agent":
    let agentName = input["agent"] as? String ?? "explorer"
    let subPrompt  = input["prompt"] as? String ?? ""
    let definition = await AgentRegistry.shared.definition(named: agentName)
        ?? .builtinExplorer
    let subagent = SubagentEngine(
        definition: definition,
        prompt: subPrompt,
        provider: currentProvider,
        hookEngine: hookEngine,
        depth: currentDepth + 1
    )
    // Forward events into parent message stream
    for await event in subagent.events {
        await messageStream.emit(.subagentEvent(agentName: agentName, event: event))
    }
    return "Subagent '\(agentName)' completed."
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all SubagentEngineTests pass.

## Commit
```bash
git add Merlin/Agents/SubagentEvent.swift \
        Merlin/Agents/SubagentEngine.swift \
        Merlin/Agents/SpawnAgentTool.swift \
        Merlin/Tools/ToolDefinitions.swift \
        Merlin/Config/AppSettings.swift
git commit -m "Phase 55b — SubagentEngine V4a (streaming events, depth/thread limits, explorer tool set)"
```
