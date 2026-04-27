import Foundation

enum AgentEvent {
    case text(String)
    case thinking(String)
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case subagentStarted(id: UUID, agentName: String)
    case subagentUpdate(id: UUID, event: SubagentEvent)
    case systemNote(String)
    case error(Error)
}

private final class CancellationState: @unchecked Sendable {
    var finished = false
}

@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    private let thinkingDetector = ThinkingModeDetector.self
    var proProvider: any LLMProvider
    var flashProvider: any LLMProvider
    private let visionProvider: any LLMProvider
    let toolRouter: ToolRouter
    var xcalibreClient: XcalibreClient?
    var registry: ProviderRegistry?
    var skillsRegistry: SkillsRegistry?
    var permissionMode: PermissionMode = .ask
    var claudeMDContent: String = ""
    var memoriesContent: String = ""

    weak var sessionStore: SessionStore?
    private var currentTask: Task<Void, Never>?
    @Published var isRunning: Bool = false

    init(proProvider: any LLMProvider,
         flashProvider: any LLMProvider,
         visionProvider: any LLMProvider,
         toolRouter: ToolRouter,
         contextManager: ContextManager,
         xcalibreClient: XcalibreClient? = nil) {
        self.proProvider = proProvider
        self.flashProvider = flashProvider
        self.visionProvider = visionProvider
        self.toolRouter = toolRouter
        self.contextManager = contextManager
        self.xcalibreClient = xcalibreClient
    }

    func registerTool(_ name: String, handler: @escaping (String) async throws -> String) {
        toolRouter.register(name: name, handler: handler)
    }

    func invokeSkill(_ skill: Skill, arguments: String = "") -> AsyncStream<AgentEvent> {
        let body = skillsRegistry?.render(skill: skill, arguments: arguments)
            ?? SkillsRegistry.renderStatic(skill: skill, arguments: arguments)

        if skill.frontmatter.context == "fork" {
            return runFork(prompt: body)
        }

        return send(userMessage: body)
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
    }

    func submitDiffComments(changeIDs: [UUID]) -> AsyncStream<AgentEvent> {
        guard let buffer = toolRouter.stagingBuffer else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let state = CancellationState()
                await withTaskCancellationHandler(operation: {
                    let message = await buffer.commentsAsAgentMessage(changeIDs)
                    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.finishStream(continuation, interrupted: false, state: state)
                        return
                    }

                    do {
                        try await self.runLoop(userMessage: message, continuation: continuation, depth: 0)
                        self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        self.finishStream(continuation, interrupted: true, state: state)
                    }
                })
            }

            Task { @MainActor in
                self.isRunning = true
                self.currentTask = task
            }
        }
    }

    func send(userMessage: String) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let state = CancellationState()
                await withTaskCancellationHandler(operation: {
                    do {
                        try await self.runLoop(userMessage: userMessage, continuation: continuation, depth: 0)
                        self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        self.finishStream(continuation, interrupted: true, state: state)
                    }
                })
            }

            Task { @MainActor in
                self.isRunning = true
                self.currentTask = task
            }
        }
    }

    private func runFork(prompt: String) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let forkContext = ContextManager()
            let task = Task { @MainActor in
                let state = CancellationState()
                await withTaskCancellationHandler(operation: {
                    do {
                        try await self.runLoop(
                            userMessage: prompt,
                            continuation: continuation,
                            contextOverride: forkContext,
                            depth: 0
                        )
                        self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        self.finishStream(continuation, interrupted: true, state: state)
                    }
                })
            }

            Task { @MainActor in
                self.isRunning = true
                self.currentTask = task
            }
        }
    }

    private func finishStream(_ continuation: AsyncStream<AgentEvent>.Continuation,
                              interrupted: Bool,
                              state: CancellationState) {
        guard !state.finished else { return }
        state.finished = true
        if interrupted {
            continuation.yield(.systemNote("[Interrupted]"))
        }
        continuation.finish()
        currentTask = nil
        isRunning = false
    }

    private func runLoop(
        userMessage: String,
        continuation: AsyncStream<AgentEvent>.Continuation,
        contextOverride: ContextManager? = nil,
        depth: Int
    ) async throws {
        let context = contextOverride ?? contextManager
        var effectiveMessage = userMessage
        if let client = xcalibreClient {
            let chunks = await client.searchChunks(query: userMessage, limit: 3, rerank: false)
            if !chunks.isEmpty {
                effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: chunks)
                continuation.yield(.systemNote("Library: \(chunks.count) passage\(chunks.count == 1 ? "" : "s") retrieved"))
            }
        }
        context.append(Message(role: .user, content: .text(effectiveMessage), timestamp: Date()))

        while true {
            let provider = selectProvider(for: userMessage)
            let requestModel = modelID(for: provider)
            let request = CompletionRequest(
                model: requestModel,
                messages: messagesForProvider(),
                thinking: shouldUseThinking(for: userMessage) ? ThinkingModeDetector.config(for: userMessage) : nil
            )

            let stream = try await provider.complete(request: request)
            var assembled: [Int: (id: String, name: String, args: String)] = [:]
            var sawToolCall = false

            for try await chunk in stream {
                if let thinkingContent = chunk.delta?.thinkingContent, !thinkingContent.isEmpty {
                    continuation.yield(.thinking(thinkingContent))
                }
                if let content = chunk.delta?.content, !content.isEmpty {
                    continuation.yield(.text(content))
                }
                if let toolCalls = chunk.delta?.toolCalls {
                    sawToolCall = true
                    for delta in toolCalls {
                        var entry = assembled[delta.index] ?? (id: "", name: "", args: "")
                        if let id = delta.id, !id.isEmpty {
                            entry.id = id
                        }
                        if let name = delta.function?.name, !name.isEmpty {
                            entry.name = name
                        }
                        entry.args += delta.function?.arguments ?? ""
                        assembled[delta.index] = entry
                    }
                }
            }

            guard sawToolCall, !assembled.isEmpty else {
                break
            }

            let calls = assembled.keys.sorted().map { index in
                let item = assembled[index]!
                return ToolCall(
                    id: item.id.isEmpty ? UUID().uuidString : item.id,
                    type: "function",
                    function: FunctionCall(name: item.name, arguments: item.args)
                )
            }

            for call in calls {
                continuation.yield(.toolCallStarted(call))
            }

            toolRouter.permissionMode = permissionMode
            var regularCalls: [ToolCall] = []
            let prevCompactionCount = context.compactionCount
            for call in calls {
                if call.function.name == "spawn_agent" {
                    await handleSpawnAgent(call: call, depth: depth, continuation: continuation)
                    continue
                }
                regularCalls.append(call)
            }

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
            if context.compactionCount != prevCompactionCount {
                continuation.yield(.systemNote("[context compacted — old tool results summarised]"))
            }
        }

        if contextOverride == nil, let session = sessionStore?.activeSession {
            var updated = session
            updated.messages = context.messages
            updated.updatedAt = Date()
            try? sessionStore?.save(updated)
        }
    }

    private func handleSpawnAgent(
        call: ToolCall,
        depth: Int,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async {
        struct SpawnArgs: Decodable {
            var agent: String
            var prompt: String
        }

        guard let args = try? JSONDecoder().decode(SpawnArgs.self, from: Data(call.function.arguments.utf8)),
              depth < AppSettings.shared.maxSubagentDepth else {
            return
        }

        let requestedDefinition = await AgentRegistry.shared.definition(named: args.agent)
        let fallbackDefinition = await AgentRegistry.shared.definition(named: "explorer")
        let definition = requestedDefinition ?? fallbackDefinition ?? AgentDefinition.defaultDefinition
        let agentID = UUID()
        continuation.yield(.subagentStarted(id: agentID, agentName: args.agent))

        let provider = registry?.primaryProvider ?? proProvider
        let hookEngine = HookEngine(hooks: AppSettings.shared.hooks)
        let subagent = SubagentEngine(
            definition: definition,
            prompt: args.prompt,
            provider: provider,
            hookEngine: hookEngine,
            depth: depth + 1
        )

        let stream = subagent.events
        await subagent.start()
        for await event in stream {
            continuation.yield(.subagentUpdate(id: agentID, event: event))
        }
    }

    func shouldUseThinking(for message: String) -> Bool {
        if let registry {
            guard let activeConfig = registry.activeConfig else { return false }
            return activeConfig.supportsThinking && thinkingDetector.shouldEnableThinking(for: message)
        }
        return thinkingDetector.shouldEnableThinking(for: message)
    }

    private func selectProvider(for message: String) -> any LLMProvider {
        if let registry {
            let lower = message.lowercased()
            if ["screenshot", "screen", "vision", "ui", "click", "button"].contains(where: { lower.contains($0) }) {
                return registry.visionProvider ?? visionProvider
            }
            if let primary = registry.primaryProvider {
                return primary
            }
        }

        let lower = message.lowercased()
        if ["screenshot", "screen", "vision", "ui", "click", "button"].contains(where: { lower.contains($0) }) {
            return visionProvider
        }
        if shouldUseThinking(for: message) {
            return proProvider
        }
        if ["read", "write", "run", "list", "build", "open", "create", "delete", "move", "show"].contains(where: { lower.contains($0) }) {
            return flashProvider
        }
        return proProvider
    }

    private func modelID(for provider: any LLMProvider) -> String {
        if let registry, let config = registry.providers.first(where: { $0.id == provider.id }) {
            if config.model.isEmpty, config.id == "lmstudio" {
                return LMStudioProvider().model
            }
            return config.model.isEmpty ? provider.id : config.model
        }
        return provider.id
    }

    private func messagesForProvider() -> [Message] {
        return messagesWithSystem(contextManager.messagesForProvider())
    }

    func messagesWithSystem(_ messages: [Message]) -> [Message] {
        let systemPrompt = buildSystemPrompt()
        guard !systemPrompt.isEmpty else { return messages }

        let systemMessage = Message(role: .system, content: .text(systemPrompt), timestamp: Date())
        if messages.first?.role == .system {
            var updated = messages
            updated[0] = systemMessage
            return updated
        } else {
            return [systemMessage] + messages
        }
    }

    private func buildSystemPrompt() -> String {
        var parts: [String] = []
        if !claudeMDContent.isEmpty {
            parts.append(claudeMDContent)
        }
        if !memoriesContent.isEmpty {
            parts.append(memoriesContent)
        }
        if permissionMode == .plan {
            parts.append(PermissionMode.planSystemPrompt)
        }
        parts.append("You are Merlin, a macOS agentic coding assistant. Use tools when helpful and keep responses concise.")
        return parts.joined(separator: "\n\n")
    }
}
