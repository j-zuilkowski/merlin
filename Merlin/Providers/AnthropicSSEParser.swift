import Foundation

enum AnthropicSSEParser {

    static func parseChunk(_ line: String) throws -> CompletionChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        guard let data = payload.data(using: .utf8) else { return nil }

        let event = try JSONDecoder().decode(AnthropicEvent.self, from: data)
        switch event.type {
        case "content_block_start":
            guard let block = event.contentBlock, block.type == "tool_use" else { return nil }
            let delta = CompletionChunk.Delta(
                toolCalls: [
                    .init(
                        index: event.index ?? 0,
                        id: block.id,
                        function: .init(name: block.name, arguments: nil)
                    )
                ]
            )
            return CompletionChunk(delta: delta, finishReason: nil)

        case "content_block_delta":
            guard let delta = event.delta else { return nil }
            switch delta.type {
            case "text_delta":
                return CompletionChunk(delta: .init(content: delta.text), finishReason: nil)
            case "thinking_delta":
                return CompletionChunk(delta: .init(thinkingContent: delta.thinking), finishReason: nil)
            case "input_json_delta":
                let toolDelta = CompletionChunk.Delta.ToolCallDelta(
                    index: event.index ?? 0,
                    id: nil,
                    function: .init(name: nil, arguments: delta.partialJson)
                )
                return CompletionChunk(delta: .init(toolCalls: [toolDelta]), finishReason: nil)
            default:
                return nil
            }

        case "message_delta":
            if let stopReason = event.delta?.stopReason {
                return CompletionChunk(delta: nil, finishReason: stopReason)
            }
            return nil

        default:
            return nil
        }
    }

    private struct AnthropicEvent: Decodable {
        var type: String
        var index: Int?
        var contentBlock: ContentBlock?
        var delta: Delta?

        enum CodingKeys: String, CodingKey {
            case type, index, delta
            case contentBlock = "content_block"
        }

        struct ContentBlock: Decodable {
            var type: String
            var id: String?
            var name: String?
        }

        struct Delta: Decodable {
            var type: String
            var text: String?
            var thinking: String?
            var partialJson: String?
            var stopReason: String?

            enum CodingKeys: String, CodingKey {
                case type, text, thinking
                case partialJson = "partial_json"
                case stopReason = "stop_reason"
            }
        }
    }
}
