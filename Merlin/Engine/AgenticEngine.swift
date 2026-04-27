import Foundation

enum AgentEvent {
    case text(String)
    case thinking(String)
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case systemNote(String)
    case error(Error)
}

private final class CancellationState: @unchecked Sendable {
    var finished = false
}

@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    private let toolRouter: ToolRouter
    private let thinkingDetector = ThinkingModeDetector.self
    var proProvider: any LLMProvider
    var flashProvider: any LLMProvider
    private let visionProvider: any LLMProvider
    var xcalibreClient: XcalibreClient?
    var registry: ProviderRegistry?

    weak var sessionStore: SessionStore?
    private var currentTask: Task<Void, Never>?

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

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func send(userMessage: String) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            var task: Task<Void, Never>!
            task = Task { @MainActor in
                let state = CancellationState()

                await withTaskCancellationHandler(operation: {
                    do {
                        try await self.runLoop(userMessage: userMessage, continuation: continuation)
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
    }

    private func runLoop(userMessage: String, continuation: AsyncStream<AgentEvent>.Continuation) async throws {
        var effectiveMessage = userMessage
        if let client = xcalibreClient {
            let chunks = await client.searchChunks(query: userMessage, limit: 3, rerank: false)
            if !chunks.isEmpty {
                effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: chunks)
                continuation.yield(.systemNote("Library: \(chunks.count) passage\(chunks.count == 1 ? "" : "s") retrieved"))
            }
        }
        contextManager.append(Message(role: .user, content: .text(effectiveMessage), timestamp: Date()))

        while true {
            let provider = selectProvider(for: userMessage)
            let requestModel = modelID(for: provider)
            let request = CompletionRequest(
                model: requestModel,
                messages: contextManager.messagesForProvider(),
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

            let results = await toolRouter.dispatch(calls)
            let prevCompactionCount = contextManager.compactionCount
            for result in results {
                continuation.yield(.toolCallResult(result))
                contextManager.append(Message(
                    role: .tool,
                    content: .text(result.content),
                    toolCallId: result.toolCallId,
                    timestamp: Date()
                ))
            }
            if contextManager.compactionCount != prevCompactionCount {
                continuation.yield(.systemNote("[context compacted — old tool results summarised]"))
            }
        }

        if let session = sessionStore?.activeSession {
            var updated = session
            updated.messages = contextManager.messages
            updated.updatedAt = Date()
            try? sessionStore?.save(updated)
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
}
