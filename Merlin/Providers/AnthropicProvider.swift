import Foundation

/// `@unchecked Sendable` rationale: URLSession-backed streaming provider; mutable state confined to async tasks.
final class AnthropicProvider: LLMProvider, @unchecked Sendable {

    let id: String = "anthropic"
    let baseURL: URL = URL(string: "https://api.anthropic.com/v1")!

    private let apiKey: String
    private let modelID: String

    static let anthropicVersion = "2023-06-01"
    static let defaultMaxTokens = 8192

    init(apiKey: String, modelID: String) {
        self.apiKey = apiKey
        self.modelID = modelID
    }

    func buildRequest(_ request: CompletionRequest) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("messages")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if request.cachePolicy.isCacheable {
            urlRequest.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        }

        var body: [String: Any] = [
            "model": request.model.isEmpty ? modelID : request.model,
            "stream": true,
            "max_tokens": request.maxTokens ?? Self.defaultMaxTokens,
            "messages": AnthropicMessageEncoder.encodeMessages(request.messages)
        ]

        if let segments = request.systemPromptSegments, request.cachePolicy.isCacheable {
            let blocks = systemBlocks(from: segments)
            if !blocks.isEmpty {
                body["system"] = blocks
            }
        } else if let systemMsg = request.messages.first(where: { $0.role == .system }),
                  case .text(let text) = systemMsg.content,
                  !text.isEmpty {
            body["system"] = request.cachePolicy.isCacheable
                ? [[
                    "type": "text",
                    "text": text,
                    "cache_control": ["type": "ephemeral"]
                ]]
                : text
        }

        if let tools = request.tools, !tools.isEmpty {
            body["tools"] = AnthropicMessageEncoder.encodeTools(tools, cachePolicy: request.cachePolicy)
        }

        if let thinking = request.thinking {
            body["thinking"] = [
                "type": thinking.type,
                "budget_tokens": 10_000
            ]
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return urlRequest
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let urlRequest = try buildRequest(request)
        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }

                    for try await line in bytes.lines {
                        if let chunk = try AnthropicSSEParser.parseChunk(line) {
                            if let usage = chunk.cacheUsage {
                                await CAGCacheMetricsStore.shared.record(usage, providerID: id)
                            }
                            continuation.yield(chunk)
                            if chunk.finishReason != nil {
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func systemBlocks(from segments: CAGSystemPromptSegments) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        let cacheable = segments.cacheable.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cacheable.isEmpty {
            blocks.append([
                "type": "text",
                "text": cacheable,
                "cache_control": ["type": "ephemeral"]
            ])
        }
        let hot = segments.hot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hot.isEmpty {
            blocks.append([
                "type": "text",
                "text": hot
            ])
        }
        return blocks
    }
}

// MARK: - Message format translation

enum AnthropicMessageEncoder {

    static func encodeMessages(_ messages: [Message]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var index = 0

        while index < messages.count {
            let message = messages[index]
            switch message.role {
            case .system:
                index += 1

            case .user:
                result.append([
                    "role": "user",
                    "content": encodeContent(message.content)
                ])
                index += 1

            case .assistant:
                if message.thinkingContent == nil,
                   message.toolCalls == nil,
                   case .text(let text) = message.content {
                    result.append(["role": "assistant", "content": text])
                } else {
                    let content = encodeAssistantContent(message)
                    if content.isEmpty {
                        result.append(["role": "assistant", "content": ""])
                    } else {
                        result.append(["role": "assistant", "content": content])
                    }
                }
                index += 1

            case .tool:
                var toolResults: [[String: Any]] = []
                while index < messages.count, messages[index].role == .tool {
                    let toolMessage = messages[index]
                    toolResults.append([
                        "type": "tool_result",
                        "tool_use_id": toolMessage.toolCallId ?? "",
                        "content": encodeToolResultContent(toolMessage.content)
                    ])
                    index += 1
                }
                result.append([
                    "role": "user",
                    "content": toolResults
                ])
            }
        }

        return result
    }

    static func encodeTools(_ tools: [ToolDefinition], cachePolicy: CAGCachePolicy = .disabled) -> [[String: Any]] {
        var encoded = tools.compactMap { tool -> [String: Any]? in
            guard let schemaData = try? JSONEncoder().encode(tool.function.parameters),
                  let schemaObject = try? JSONSerialization.jsonObject(with: schemaData) else {
                return nil
            }

            return [
                "name": tool.function.name,
                "description": tool.function.description,
                "input_schema": schemaObject
            ]
        }

        if cachePolicy.isCacheable, let lastIndex = encoded.indices.last {
            encoded[lastIndex]["cache_control"] = ["type": "ephemeral"]
        }

        return encoded
    }

    private static func encodeAssistantContent(_ message: Message) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        if let thinking = message.thinkingContent, !thinking.isEmpty {
            blocks.append([
                "type": "thinking",
                "thinking": thinking
            ])
        }

        switch message.content {
        case .text(let text):
            if !text.isEmpty {
                blocks.append([
                    "type": "text",
                    "text": text
                ])
            }
        case .parts(let parts):
            blocks.append(contentsOf: parts.compactMap { part in
                switch part {
                case .text(let text):
                    return [
                        "type": "text",
                        "text": text
                    ]
                case .imageURL(let url):
                    return [
                        "type": "text",
                        "text": "[image: \(url)]"
                    ]
                }
            })
        }

        if let toolCalls = message.toolCalls {
            blocks.append(contentsOf: toolCalls.map { call in
                var block: [String: Any] = [
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.function.name
                ]
                if let data = call.function.arguments.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    block["input"] = json
                } else {
                    block["input"] = [:] as [String: Any]
                }
                return block
            })
        }

        return blocks
    }

    private static func encodeContent(_ content: MessageContent) -> Any {
        switch content {
        case .text(let text):
            return text
        case .parts(let parts):
            return parts.compactMap { part -> [String: Any]? in
                switch part {
                case .text(let text):
                    return ["type": "text", "text": text]
                case .imageURL(let url):
                    return ["type": "text", "text": "[image: \(url)]"]
                }
            }
        }
    }

    private static func encodeToolResultContent(_ content: MessageContent) -> Any {
        switch content {
        case .text(let text):
            return text
        case .parts(let parts):
            return parts.compactMap { part -> [String: Any]? in
                switch part {
                case .text(let text):
                    return ["type": "text", "text": text]
                case .imageURL(let url):
                    return ["type": "text", "text": "[image: \(url)]"]
                }
            }
        }
    }
}
