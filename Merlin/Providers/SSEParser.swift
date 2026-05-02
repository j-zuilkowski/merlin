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
                case reasoningContent = "reasoning_content"   // DeepSeek field name
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                role = try c.decodeIfPresent(String.self, forKey: .role)
                content = try c.decodeIfPresent(String.self, forKey: .content)
                toolCalls = try c.decodeIfPresent([ToolCallDelta].self, forKey: .toolCalls)
                // Accept both naming conventions; prefer reasoning_content (DeepSeek).
                thinkingContent = try c.decodeIfPresent(String.self, forKey: .reasoningContent)
                    ?? c.decodeIfPresent(String.self, forKey: .thinkingContent)
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
            // DeepSeek and OpenAI-compatible providers expect "reasoning_content".
            case thinkingContent = "reasoning_content"
        }

        init(_ message: Message) {
            self.role = message.role
            var wc = WireContent(message.content)
            // Tool result messages must encode content as a string, never null.
            wc.requiresStringContent = (message.role == .tool)
            self.content = wc
            self.toolCalls = message.toolCalls
            self.toolCallId = message.toolCallId
            self.thinkingContent = message.thinkingContent
        }
    }

    struct WireContent: Encodable {
        var text: String?
        var parts: [ContentPart]?
        /// When true, encodes as `""` instead of `null` for empty/nil content.
        /// Required for role=tool messages: DeepSeek (and OpenAI spec) require
        /// content to be a string or list — never null — for tool result messages.
        var requiresStringContent: Bool = false

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
            // OpenAI wire format: assistant messages carrying only tool_calls must
            // send content: null (not ""). An empty string is rejected by DeepSeek
            // and other OpenAI-compatible providers with a 400/bad-response error.
            // However, role=tool (tool result) messages must always be a string.
            if let text, !text.isEmpty {
                try c.encode(text)
            } else if let parts {
                try c.encode(parts)
            } else if requiresStringContent {
                try c.encode("")
            } else {
                try c.encodeNil()
            }
        }
    }

    /// Request body for OpenAI-compatible completions.
    /// Synthesized optionals behave like `encodeIfPresent`, so nil fields are omitted.
    struct Body: Encodable {
        var model: String
        var messages: [WireMessage]
        var tools: [ToolDefinition]?
        var stream: Bool
        var thinking: ThinkingConfig?
        var maxTokens: Int?
        var temperature: Double?
        var topP: Double?
        var topK: Int?
        var minP: Double?
        var repeatPenalty: Double?
        var frequencyPenalty: Double?
        var presencePenalty: Double?
        var seed: Int?
        var stop: [String]?

        enum CodingKeys: String, CodingKey {
            case model, messages, tools, stream, thinking, temperature
            /// `seed` ↔ `seed`.
            case seed
            /// `stop` ↔ `stop`.
            case stop
            /// `maxTokens` ↔ `max_tokens`.
            case maxTokens = "max_tokens"
            /// `topP` ↔ `top_p`.
            case topP = "top_p"
            /// `topK` ↔ `top_k`.
            case topK = "top_k"
            /// `minP` ↔ `min_p`.
            case minP = "min_p"
            /// `repeatPenalty` ↔ `repeat_penalty`.
            case repeatPenalty = "repeat_penalty"
            /// `frequencyPenalty` ↔ `frequency_penalty`.
            case frequencyPenalty = "frequency_penalty"
            /// `presencePenalty` ↔ `presence_penalty`.
            case presencePenalty = "presence_penalty"
        }
    }

    let body = Body(
        model: request.model.isEmpty ? model : request.model,
        messages: request.messages.map(WireMessage.init),
        tools: request.tools,
        stream: request.stream,
        thinking: includeThinking ? request.thinking : nil,
        maxTokens: request.maxTokens,
        temperature: request.temperature,
        topP: request.topP,
        topK: request.topK,
        minP: request.minP,
        repeatPenalty: request.repeatPenalty,
        frequencyPenalty: request.frequencyPenalty,
        presencePenalty: request.presencePenalty,
        seed: request.seed,
        stop: request.stop
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(body)
}
