import Foundation

struct Message: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var role: Role
    var content: MessageContent
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var thinkingContent: String?
    var timestamp: Date

    enum Role: String, Codable, Sendable { case user, assistant, tool, system }

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case thinkingContent = "thinking_content"
        case timestamp
    }
}

enum MessageContent: Codable, Sendable {
    case text(String)
    case parts([ContentPart])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .text(s)
            return
        }
        self = .parts(try c.decode([ContentPart].self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s):
            try c.encode(s)
        case .parts(let p):
            try c.encode(p)
        }
    }
}

enum ContentPart: Codable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey { case type, text, image_url }
    private struct ImageURL: Codable, Sendable { var url: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "image_url":
            let img = try c.decode(ImageURL.self, forKey: .image_url)
            self = .imageURL(img.url)
        default:
            self = .text(try c.decode(String.self, forKey: .text))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
        case .imageURL(let url):
            try c.encode("image_url", forKey: .type)
            try c.encode(ImageURL(url: url), forKey: .image_url)
        }
    }
}

struct ToolCall: Codable, Sendable {
    var id: String
    var type: String
    var function: FunctionCall
}

struct FunctionCall: Codable, Sendable {
    var name: String
    var arguments: String
}

struct ToolResult: Codable, Sendable {
    var toolCallId: String
    var content: String
    var isError: Bool
}

/// OpenAI-compatible completion payload used by Merlin's provider adapters.
///
/// Optional fields are omitted from the encoded JSON when nil, so provider
/// defaults remain in effect unless `AppSettings.applyInferenceDefaults(to:)`
/// fills them first.
struct CompletionRequest: Sendable {
    /// Target model identifier.
    var model: String
    /// Ordered chat messages sent to the model.
    var messages: [Message]
    /// Tool definitions exposed to the provider for this turn.
    var tools: [ToolDefinition]?
    /// Streams deltas instead of waiting for a single final completion.
    var stream: Bool = true
    /// Optional reasoning/thinking configuration for providers that support it.
    var thinking: ThinkingConfig?
    /// Maximum generated tokens; `nil` keeps the provider or app default.
    var maxTokens: Int?
    /// Temperature sampling factor; `nil` keeps the provider or app default.
    var temperature: Double?
    /// Nucleus sampling probability, usually `0...1`; `nil` keeps defaults.
    var topP: Double?
    /// Top-k cutoff; provider-specific positive integer, `nil` keeps defaults.
    var topK: Int?
    /// Minimum probability filter, usually `0...1`; `nil` keeps defaults.
    var minP: Double?
    /// Repetition penalty, usually `1.0...2.0`; `nil` keeps defaults.
    var repeatPenalty: Double?
    /// Frequency penalty adjustment, usually `-2.0...2.0`; `nil` keeps defaults.
    var frequencyPenalty: Double?
    /// Presence penalty adjustment, usually `-2.0...2.0`; `nil` keeps defaults.
    var presencePenalty: Double?
    /// Deterministic sampling seed; `nil` keeps provider randomness.
    var seed: Int?
    /// Stop sequences that terminate generation; `nil` or empty keeps defaults.
    var stop: [String]?
}

struct ThinkingConfig: Codable, Sendable {
    var type: String
    var reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case type
        case reasoningEffort = "reasoning_effort"
    }
}

struct CompletionChunk: Sendable {
    var delta: Delta?
    var finishReason: String?

    init(delta: Delta?, finishReason: String?) {
        self.delta = delta
        self.finishReason = finishReason
    }

    struct Delta: Sendable {
        var role: String?
        var content: String?
        var toolCalls: [ToolCallDelta]?
        var thinkingContent: String?

        init(role: String? = nil,
             content: String? = nil,
             toolCalls: [ToolCallDelta]? = nil,
             thinkingContent: String? = nil) {
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
            self.thinkingContent = thinkingContent
        }

        struct ToolCallDelta: Sendable {
            var index: Int
            var id: String?
            var function: FunctionDelta?

            init(index: Int, id: String? = nil, function: FunctionDelta? = nil) {
                self.index = index
                self.id = id
                self.function = function
            }

            struct FunctionDelta: Sendable {
                var name: String?
                var arguments: String?

                init(name: String? = nil, arguments: String? = nil) {
                    self.name = name
                    self.arguments = arguments
                }
            }
        }
    }
}

typealias ChunkDelta = CompletionChunk.Delta

struct ToolDefinition: Codable, Sendable {
    var type: String = "function"
    var function: FunctionDefinition

    init(type: String = "function", function: FunctionDefinition) {
        self.type = type
        self.function = function
    }

    struct FunctionDefinition: Codable, Sendable {
        var name: String
        var description: String
        var parameters: JSONSchema
        var strict: Bool?

        init(name: String, description: String, parameters: JSONSchema, strict: Bool? = nil) {
            self.name = name
            self.description = description
            self.parameters = parameters
            self.strict = strict
        }
    }
}

final class JSONSchema: Codable, @unchecked Sendable {
    var type: String
    var properties: [String: JSONSchema]?
    var required: [String]?
    var items: JSONSchema?
    var description: String?
    var enumValues: [String]?

    init(type: String,
         properties: [String: JSONSchema]? = nil,
         required: [String]? = nil,
         items: JSONSchema? = nil,
         description: String? = nil,
         enumValues: [String]? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
        self.items = items
        self.description = description
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type, properties, required, items, description
        case enumValues = "enum"
    }
}

protocol LLMProvider: AnyObject, Sendable {
    var id: String { get }
    var baseURL: URL { get }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error>
}
