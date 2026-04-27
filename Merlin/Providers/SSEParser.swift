import Foundation

enum SSEParser {
    static func parseChunk(_ line: String) throws -> CompletionChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]" else { return nil }
        guard let data = payload.data(using: .utf8) else { return nil }

        let response = try JSONDecoder().decode(RawChunk.self, from: data)
        guard let choice = response.choices.first else { return nil }
        let delta = choice.delta.map {
            CompletionChunk.Delta(
                role: $0.role,
                content: $0.content,
                toolCalls: $0.toolCalls?.map {
                    CompletionChunk.Delta.ToolCallDelta(
                        index: $0.index,
                        id: $0.id,
                        function: $0.function.map {
                            CompletionChunk.Delta.ToolCallDelta.FunctionDelta(
                                name: $0.name,
                                arguments: $0.arguments
                            )
                        }
                    )
                },
                thinkingContent: $0.thinkingContent
            )
        }
        return CompletionChunk(delta: delta, finishReason: choice.finishReason)
    }

    private struct RawChunk: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var delta: Delta?
            var finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        struct Delta: Decodable {
            var role: String?
            var content: String?
            var toolCalls: [ToolCallDelta]?
            var thinkingContent: String?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
                case thinkingContent = "thinking_content"
            }
        }

        struct ToolCallDelta: Decodable {
            var index: Int
            var id: String?
            var function: FunctionDelta?

            struct FunctionDelta: Decodable {
                var name: String?
                var arguments: String?
            }
        }
    }
}

func encodeRequest(_ request: CompletionRequest, baseURL: URL, model: String, includeThinking: Bool = true) throws -> Data {
    struct WireMessage: Encodable {
        var role: Message.Role
        var content: WireContent
        var toolCalls: [ToolCall]?
        var toolCallId: String?
        var thinkingContent: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolCallId = "tool_call_id"
            case thinkingContent = "thinking_content"
        }

        init(_ message: Message) {
            self.role = message.role
            self.content = WireContent(message.content)
            self.toolCalls = message.toolCalls
            self.toolCallId = message.toolCallId
            self.thinkingContent = message.thinkingContent
        }
    }

    struct WireContent: Encodable {
        var text: String?
        var parts: [ContentPart]?

        init(_ content: MessageContent) {
            switch content {
            case .text(let s):
                self.text = s
                self.parts = nil
            case .parts(let parts):
                self.text = nil
                self.parts = parts
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            if let text {
                try c.encode(text)
            } else if let parts {
                try c.encode(parts)
            } else {
                try c.encodeNil()
            }
        }
    }

    struct Body: Encodable {
        var model: String
        var messages: [WireMessage]
        var tools: [ToolDefinition]?
        var stream: Bool
        var thinking: ThinkingConfig?
        var maxTokens: Int?
        var temperature: Double?

        enum CodingKeys: String, CodingKey {
            case model, messages, tools, stream, thinking
            case maxTokens = "max_tokens"
            case temperature
        }
    }

    let body = Body(
        model: request.model.isEmpty ? model : request.model,
        messages: request.messages.map(WireMessage.init),
        tools: request.tools,
        stream: request.stream,
        thinking: includeThinking ? request.thinking : nil,
        maxTokens: request.maxTokens,
        temperature: request.temperature
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(body)
}
