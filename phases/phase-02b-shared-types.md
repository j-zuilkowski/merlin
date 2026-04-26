# Phase 02b — Shared Types: Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

## Write to: Merlin/Providers/LLMProvider.swift

Implement exactly these types. Use snake_case CodingKeys where JSON keys differ.
All value types must conform to `Sendable` — they cross actor boundaries in the engine.

```swift
import Foundation

// MARK: - Message

struct Message: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var role: Role
    var content: MessageContent
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var thinkingContent: String?
    var timestamp: Date

    enum Role: String, Codable { case user, assistant, tool, system }

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case thinkingContent = "thinking_content"
        case timestamp
    }
}

// MARK: - MessageContent

enum MessageContent: Codable, Sendable {
    case text(String)
    case parts([ContentPart])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s); return }
        self = .parts(try c.decode([ContentPart].self))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .parts(let p): try c.encode(p)
        }
    }
}

// MARK: - ContentPart

enum ContentPart: Codable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey { case type, text, image_url }
    private struct ImageURL: Codable { var url: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        switch type_ {
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

// MARK: - Tool Call

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

// MARK: - Completion

struct CompletionRequest: Sendable {
    var model: String
    var messages: [Message]
    var tools: [ToolDefinition]?
    var stream: Bool = true
    var thinking: ThinkingConfig?
    var maxTokens: Int?
    var temperature: Double?
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

    struct Delta: Sendable {
        var role: String?
        var content: String?
        var toolCalls: [ToolCallDelta]?
        var thinkingContent: String?
    }

    struct ToolCallDelta: Sendable {
        var index: Int
        var id: String?
        var function: FunctionDelta?

        struct FunctionDelta: Sendable {
            var name: String?
            var arguments: String?
        }
    }
}

// MARK: - Tool Definition

struct ToolDefinition: Codable, Sendable {
    var type: String = "function"
    var function: FunctionDefinition

    struct FunctionDefinition: Codable, Sendable {
        var name: String
        var description: String
        var parameters: JSONSchema
        var strict: Bool?
    }
}

struct JSONSchema: Codable, Sendable {
    var type: String
    var properties: [String: JSONSchema]?
    var required: [String]?
    var items: JSONSchema?
    var description: String?
    var enumValues: [String]?
    enum CodingKeys: String, CodingKey {
        case type, properties, required, items, description
        case enumValues = "enum"
    }
}

// MARK: - LLMProvider protocol

// Sendable required: instances are held by @MainActor AgenticEngine
// and complete() is called inside child Tasks.
// Concrete providers are final classes with only let-stored constants → @unchecked Sendable is safe.
protocol LLMProvider: AnyObject, Sendable {
    var id: String { get }
    var baseURL: URL { get }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error>
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/SharedTypesTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'SharedTypesTests' passed` with 5 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/LLMProvider.swift
git commit -m "Phase 02b — Shared types + LLMProvider protocol (all Sendable)"
```
