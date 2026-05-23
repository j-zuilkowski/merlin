import Foundation

typealias SubagentToolDefinitionsProvider = @MainActor @Sendable () -> [ToolDefinition]
typealias SubagentToolExecutor = @MainActor @Sendable (ToolCall) async -> ToolResult

struct StreamedToolCallAssembler {
    private var entries: [Int: (id: String, name: String, args: String)] = [:]

    mutating func append(_ deltas: [CompletionChunk.Delta.ToolCallDelta]) {
        for delta in deltas {
            var entry = entries[delta.index] ?? (id: "", name: "", args: "")
            if let id = delta.id, id.isEmpty == false {
                entry.id = id
            }
            if let name = delta.function?.name, name.isEmpty == false {
                entry.name = name
            }
            entry.args += delta.function?.arguments ?? ""
            entries[delta.index] = entry
        }
    }

    var calls: [ToolCall] {
        entries
            .sorted { $0.key < $1.key }
            .compactMap { _, entry in
                guard entry.id.isEmpty == false, entry.name.isEmpty == false else {
                    return nil
                }
                return ToolCall(
                    id: entry.id,
                    type: "function",
                    function: FunctionCall(name: entry.name, arguments: entry.args)
                )
            }
    }
}

actor SubagentEngine {
    private let definition: AgentDefinition
    private let prompt: String
    private let provider: any LLMProvider
    /// Model id to send when the agent definition pins no model of its own.
    /// Must be the *resolved* id for `provider` (e.g. `qwen/qwen3-coder-next`),
    /// never a provider id — an empty/garbage model makes the request go out as
    /// the bare provider id ("lmstudio"), which the backend rejects and which
    /// silently broke every spawned subagent (observed sabotaging S1).
    private let fallbackModel: String
    private let hookEngine: HookEngine
    private let depth: Int
    private let toolDefinitionsProvider: SubagentToolDefinitionsProvider
    private let toolExecutor: SubagentToolExecutor

    private var continuation: AsyncStream<SubagentEvent>.Continuation?
    private var runTask: Task<Void, Never>?
    private var started = false

    init(
        definition: AgentDefinition,
        prompt: String,
        provider: any LLMProvider,
        fallbackModel: String = "",
        hookEngine: HookEngine,
        depth: Int,
        toolDefinitionsProvider: @escaping SubagentToolDefinitionsProvider = { ToolRegistry.shared.all() },
        toolExecutor: @escaping SubagentToolExecutor = { call in
            ToolResult(
                toolCallId: call.id,
                content: "Unknown tool: \(call.function.name)",
                isError: true
            )
        }
    ) {
        self.definition = definition
        self.prompt = prompt
        self.provider = provider
        self.fallbackModel = fallbackModel
        self.hookEngine = hookEngine
        self.depth = depth
        self.toolDefinitionsProvider = toolDefinitionsProvider
        self.toolExecutor = toolExecutor
    }

    nonisolated var events: AsyncStream<SubagentEvent> {
        AsyncStream { continuation in
            Task { await self.attachContinuation(continuation) }
        }
    }

    func start() async {
        startIfNeeded()
    }

    nonisolated func cancel() {
        Task { await self.finishCancellation() }
    }

    nonisolated func availableToolNames() -> [String] {
        let maxDepth = 2
        let baseTools: [String]
        switch definition.role {
        case .explorer:
            baseTools = definition.allowedTools ?? AgentDefinition.explorerToolSet
        case .worker, .default:
            baseTools = definition.allowedTools ?? ToolDefinitions.all.map { $0.function.name }
        }

        var tools = baseTools
        if depth < maxDepth, tools.contains("spawn_agent") == false {
            tools.append("spawn_agent")
        }
        if depth >= maxDepth {
            tools.removeAll { $0 == "spawn_agent" }
        }
        return tools
    }

    private func attachContinuation(_ continuation: AsyncStream<SubagentEvent>.Continuation) {
        self.continuation = continuation
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard started == false else {
            return
        }
        started = true
        runTask = Task { await run() }
    }

    private func finishCancellation() {
        runTask?.cancel()
        runTask = nil
        continuation?.finish()
    }

    private func run() async {
        guard Task.isCancelled == false else {
            continuation?.finish()
            return
        }

        let context = await MainActor.run { ContextManager() }
        await context.append(Message(role: .system, content: .text(buildSystemPrompt()), timestamp: Date()))
        await context.append(Message(role: .user, content: .text(prompt), timestamp: Date()))

        var iterations = 0
        let maxIterations = 30

        do {
            while Task.isCancelled == false, iterations < maxIterations {
                iterations += 1

                var request = CompletionRequest(
                    model: definition.model ?? fallbackModel,
                    messages: await context.messagesForProvider(),
                    tools: await toolDefinitions(),
                    stream: true,
                    thinking: nil,
                    maxTokens: nil,
                    temperature: nil
                )
                let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
                inferenceDefaults.apply(to: &request)

                let stream = try await PreflightGuard.complete(request, provider: provider)
                var accumulated = ""
                var accumulatedThinking = ""
                var assembler = StreamedToolCallAssembler()

                for try await chunk in stream {
                    if Task.isCancelled {
                        break
                    }
                    if let text = chunk.delta?.content, text.isEmpty == false {
                        accumulated += text
                        continuation?.yield(.messageChunk(text))
                    }
                    if let thinking = chunk.delta?.thinkingContent, thinking.isEmpty == false {
                        accumulatedThinking += thinking
                    }
                    if let toolCalls = chunk.delta?.toolCalls {
                        assembler.append(toolCalls)
                    }
                }

                let calls = assembler.calls
                if calls.isEmpty == false {
                    await context.append(Message(
                        role: .assistant,
                        content: .text(accumulated),
                        toolCalls: calls,
                        thinkingContent: accumulatedThinking.isEmpty ? nil : accumulatedThinking,
                        timestamp: Date()
                    ))
                    await executeToolCalls(calls, into: context)
                    continue
                }

                await context.append(Message(
                    role: .assistant,
                    content: .text(accumulated),
                    thinkingContent: accumulatedThinking.isEmpty ? nil : accumulatedThinking,
                    timestamp: Date()
                ))
                continuation?.yield(.completed(summary: accumulated))
                continuation?.finish()
                return
            }

            continuation?.yield(.completed(summary: "Subagent reached iteration limit."))
            continuation?.finish()
        } catch {
            continuation?.yield(.failed(error))
            continuation?.finish()
        }
    }

    private func buildSystemPrompt() -> String {
        if definition.instructions.isEmpty {
            return "You are a subagent. Complete your assigned task and stop."
        }
        return "\(definition.instructions)\n\nYou are a subagent. Complete your assigned task and stop."
    }

    private func toolDefinitions() async -> [ToolDefinition] {
        let names = Set(availableToolNames())
        let tools = await toolDefinitionsProvider()
        return tools.filter { names.contains($0.function.name) }
    }

    private func executeToolCalls(_ calls: [ToolCall], into context: ContextManager) async {
        for call in calls {
            let input = inputDictionary(from: call.function.arguments)
            continuation?.yield(.toolCallStarted(toolName: call.function.name, input: input))

            let result: ToolResult
            if call.function.name == "spawn_agent" {
                result = ToolResult(
                    toolCallId: call.id,
                    content: "spawn_agent is not supported from inside a subagent yet. Complete the remaining work yourself.",
                    isError: true
                )
            } else {
                let hookDecision = await hookEngine.runPreToolUse(
                    toolName: call.function.name,
                    input: input
                )
                switch hookDecision {
                case .allow:
                    result = await toolExecutor(call)
                case .deny(let reason):
                    result = ToolResult(
                        toolCallId: call.id,
                        content: "Tool blocked by hook: \(reason)",
                        isError: true
                    )
                }
            }

            continuation?.yield(.toolCallCompleted(toolName: call.function.name, result: result.content))
            await context.append(Message(
                role: .tool,
                content: .text(result.content),
                toolCallId: call.id,
                timestamp: Date()
            ))

            if let note = await hookEngine.runPostToolUse(
                toolName: call.function.name,
                result: result.content
            ) {
                await context.append(Message(role: .system, content: .text(note), timestamp: Date()))
            }
        }
    }

    private func inputDictionary(from arguments: String) -> [String: String] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dictionary = json as? [String: Any] else {
            return [:]
        }

        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = String(describing: pair.value)
        }
    }
}
