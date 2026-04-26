import Foundation

enum AgentEvent {
    case text(String)
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case systemNote(String)
    case error(Error)
}

@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    private let toolRouter: ToolRouter
    private let proProvider: any LLMProvider
    private let flashProvider: any LLMProvider
    private let visionProvider: LMStudioProvider

    weak var sessionStore: SessionStore?

    init(proProvider: any LLMProvider,
         flashProvider: any LLMProvider,
         visionProvider: LMStudioProvider,
         toolRouter: ToolRouter,
         contextManager: ContextManager) {
        self.proProvider = proProvider
        self.flashProvider = flashProvider
        self.visionProvider = visionProvider
        self.toolRouter = toolRouter
        self.contextManager = contextManager
    }

    func registerTool(_ name: String, handler: @escaping (String) async throws -> String) {
        toolRouter.register(name: name, handler: handler)
    }

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

    private func runLoop(userMessage: String, continuation: AsyncStream<AgentEvent>.Continuation) async throws {
        contextManager.append(Message(role: .user, content: .text(userMessage), timestamp: Date()))

        if contextManager.messages.contains(where: {
            if $0.role == .system, case .text(let text) = $0.content {
                return text.contains("compacted")
            }
            return false
        }) {
            continuation.yield(.systemNote("[context compacted]"))
        }

        while true {
            let provider = selectProvider(for: userMessage)
            let request = CompletionRequest(
                model: provider.id,
                messages: contextManager.messagesForProvider(),
                thinking: provider.id == proProvider.id ? ThinkingModeDetector.config(for: userMessage) : nil
            )

            let stream = try await provider.complete(request: request)
            var assembled: [Int: (id: String, name: String, args: String)] = [:]
            var sawToolCall = false

            for try await chunk in stream {
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
            for result in results {
                continuation.yield(.toolCallResult(result))
                contextManager.append(Message(
                    role: .tool,
                    content: .text(result.content),
                    toolCallId: result.toolCallId,
                    timestamp: Date()
                ))
            }
        }

        if let session = sessionStore?.activeSession {
            var updated = session
            updated.messages = contextManager.messages
            updated.updatedAt = Date()
            try? sessionStore?.save(updated)
        }
    }

    private func selectProvider(for message: String) -> any LLMProvider {
        let lower = message.lowercased()
        if ["screenshot", "screen", "vision", "ui", "click", "button"].contains(where: { lower.contains($0) }) {
            return visionProvider
        }
        if ThinkingModeDetector.shouldEnableThinking(for: message) {
            return proProvider
        }
        if ["read", "write", "run", "list", "build", "open", "create", "delete", "move", "show"].contains(where: { lower.contains($0) }) {
            return flashProvider
        }
        return proProvider
    }
}
