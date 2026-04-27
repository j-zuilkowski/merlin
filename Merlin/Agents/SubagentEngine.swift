import Foundation

actor SubagentEngine {
    private let definition: AgentDefinition
    private let prompt: String
    private let provider: any LLMProvider
    private let hookEngine: HookEngine
    private let depth: Int

    private var continuation: AsyncStream<SubagentEvent>.Continuation?
    private var runTask: Task<Void, Never>?
    private var started = false

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

        do {
            let request = CompletionRequest(
                model: definition.model ?? "",
                messages: await context.messagesForProvider(),
                tools: await toolDefinitions(),
                stream: true,
                thinking: nil,
                maxTokens: nil,
                temperature: nil
            )
            let stream = try await provider.complete(request: request)
            var accumulated = ""
            for try await chunk in stream {
                if Task.isCancelled {
                    break
                }
                if let text = chunk.delta?.content, text.isEmpty == false {
                    accumulated += text
                    continuation?.yield(.messageChunk(text))
                }
                if let toolCalls = chunk.delta?.toolCalls {
                    for call in toolCalls {
                        guard let function = call.function,
                              let name = function.name,
                              let arguments = function.arguments else {
                            continue
                        }
                        let input = inputDictionary(from: arguments)
                        continuation?.yield(.toolCallStarted(toolName: name, input: input))
                        continuation?.yield(.toolCallCompleted(toolName: name, result: arguments))
                    }
                }
                if chunk.finishReason != nil {
                    break
                }
            }
            continuation?.yield(.completed(summary: accumulated))
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
        let names = availableToolNames()
        let tools = await ToolRegistry.shared.all()
        return tools.filter { names.contains($0.function.name) }
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
