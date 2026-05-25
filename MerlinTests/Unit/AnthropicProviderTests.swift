import XCTest
@testable import Merlin

// MARK: - AnthropicSSEParserTests

final class AnthropicSSEParserTests: XCTestCase {

    func testParsesTextDelta() throws {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        XCTAssertEqual(chunk?.delta?.content, "Hello")
        XCTAssertNil(chunk?.delta?.thinkingContent)
    }

    func testParsesThinkingDelta() throws {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Reasoning..."}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        XCTAssertEqual(chunk?.delta?.thinkingContent, "Reasoning...")
        XCTAssertNil(chunk?.delta?.content)
    }

    func testParsesInputJsonDelta() throws {
        let line = #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        let toolDelta = chunk?.delta?.toolCalls?.first
        XCTAssertNotNil(toolDelta)
        XCTAssertEqual(toolDelta?.index, 1)
        XCTAssertEqual(toolDelta?.function?.arguments, "{\"path\":")
    }

    func testParsesContentBlockStartToolUse() throws {
        let line = #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"call_abc","name":"read_file","input":{}}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        let toolDelta = chunk?.delta?.toolCalls?.first
        XCTAssertEqual(toolDelta?.id, "call_abc")
        XCTAssertEqual(toolDelta?.function?.name, "read_file")
        XCTAssertEqual(toolDelta?.index, 1)
    }

    func testIgnoresNonDataLines() throws {
        let chunk = try AnthropicSSEParser.parseChunk("event: content_block_start")
        XCTAssertNil(chunk)
    }

    func testIgnoresDoneMarker() throws {
        let chunk = try AnthropicSSEParser.parseChunk("data: [DONE]")
        XCTAssertNil(chunk)
    }

    func testIgnoresEmptyLine() throws {
        let chunk = try AnthropicSSEParser.parseChunk("")
        XCTAssertNil(chunk)
    }


    func testAnthropicSSEParserParsesCacheUsage() throws {
        let line = #"data: {"type":"message_delta","usage":{"input_tokens":100,"cache_read_input_tokens":80,"cache_creation_input_tokens":20}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        XCTAssertEqual(chunk?.cacheUsage?.readTokens, 80)
        XCTAssertEqual(chunk?.cacheUsage?.creationTokens, 20)
        XCTAssertEqual(chunk?.cacheUsage?.uncachedInputTokens, 100)
    }
}

// MARK: - AnthropicMessageEncoderTests

final class AnthropicMessageEncoderTests: XCTestCase {

    func testEncodeUserMessage() {
        let messages = [Message(role: .user, content: .text("Hello"), timestamp: Date())]
        let encoded = AnthropicMessageEncoder.encodeMessages(messages)
        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded[0]["role"] as? String, "user")
    }

    func testEncodeAssistantTextMessage() {
        let messages = [Message(role: .assistant, content: .text("Hi"), timestamp: Date())]
        let encoded = AnthropicMessageEncoder.encodeMessages(messages)
        XCTAssertEqual(encoded[0]["role"] as? String, "assistant")
    }

    func testToolResultGroupedIntoUserMessage() {
        let messages = [
            Message(
                role: .assistant,
                content: .text(""),
                toolCalls: [ToolCall(id: "call_1", type: "function",
                                    function: FunctionCall(name: "read_file", arguments: "{}"))],
                timestamp: Date()
            ),
            Message(role: .tool, content: .text("file contents"), toolCallId: "call_1",
                    timestamp: Date())
        ]
        let encoded = AnthropicMessageEncoder.encodeMessages(messages)
        let toolResultMsg = encoded.first {
            guard $0["role"] as? String == "user",
                  let content = $0["content"] as? [[String: Any]] else { return false }
            return content.first?["type"] as? String == "tool_result"
        }
        XCTAssertNotNil(toolResultMsg, "Tool result should be a user-role message with tool_result content")
    }

    func testMultipleToolResultsGrouped() {
        let messages = [
            Message(
                role: .assistant, content: .text(""),
                toolCalls: [
                    ToolCall(id: "c1", type: "function", function: FunctionCall(name: "read_file", arguments: "{}")),
                    ToolCall(id: "c2", type: "function", function: FunctionCall(name: "list_directory", arguments: "{}"))
                ],
                timestamp: Date()
            ),
            Message(role: .tool, content: .text("file contents"), toolCallId: "c1", timestamp: Date()),
            Message(role: .tool, content: .text("dir listing"), toolCallId: "c2", timestamp: Date())
        ]
        let encoded = AnthropicMessageEncoder.encodeMessages(messages)
        let toolResultMsg = encoded.first { $0["role"] as? String == "user" }
        let content = toolResultMsg?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2, "Both tool results should be in a single user message")
    }

    func testEncodeToolDefinitions() {
        let tools = [ToolDefinition(function: .init(
            name: "read_file",
            description: "Read a file",
            parameters: JSONSchema(
                type: "object",
                properties: ["path": JSONSchema(type: "string", description: "File path")],
                required: ["path"]
            )
        ))]
        let encoded = AnthropicMessageEncoder.encodeTools(tools)
        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded[0]["name"] as? String, "read_file")
        XCTAssertNotNil(encoded[0]["input_schema"], "Anthropic uses input_schema not parameters")
        XCTAssertNil(encoded[0]["parameters"], "parameters key must not appear")
    }

    func testCAGEnabledAddsPromptCachingBetaHeader() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        var req = CompletionRequest(model: "claude-opus-4-7", messages: [
            Message(role: .system, content: .text("System text"), timestamp: Date())
        ], tools: nil)
        req.cachePolicy = .ephemeral

        let urlRequest = try provider.buildRequest(req)
        XCTAssertTrue(urlRequest.value(forHTTPHeaderField: "anthropic-beta")?.contains("prompt-caching-2024-07-31") == true)
    }

    func testCAGEnabledMarksSystemBlockEphemeral() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        var req = CompletionRequest(model: "claude-opus-4-7", messages: [
            Message(role: .system, content: .text("System text"), timestamp: Date())
        ], tools: nil)
        req.cachePolicy = .ephemeral

        let urlRequest = try provider.buildRequest(req)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(urlRequest.httpBody)) as! [String: Any]
        let system = body["system"] as? [[String: Any]]
        let first = system?.first
        XCTAssertEqual(first?["type"] as? String, "text")
        XCTAssertEqual((first?["cache_control"] as? [String: Any])?["type"] as? String, "ephemeral")
    }

    func testCAGEnabledMarksLastToolEphemeral() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let tools = [
            ToolDefinition(function: .init(name: "alpha", description: "a", parameters: JSONSchema(type: "object"))),
            ToolDefinition(function: .init(name: "beta", description: "b", parameters: JSONSchema(type: "object"))),
        ]
        var req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: tools)
        req.cachePolicy = .ephemeral

        let urlRequest = try provider.buildRequest(req)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(urlRequest.httpBody)) as! [String: Any]
        let encodedTools = body["tools"] as? [[String: Any]]
        let last = encodedTools?.last
        XCTAssertEqual((last?["cache_control"] as? [String: Any])?["type"] as? String, "ephemeral")
    }

    func testCAGDisabledKeepsLegacySystemString() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        var req = CompletionRequest(model: "claude-opus-4-7", messages: [
            Message(role: .system, content: .text("System text"), timestamp: Date())
        ], tools: nil)
        req.cachePolicy = .disabled

        let urlRequest = try provider.buildRequest(req)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "anthropic-beta"))

        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(urlRequest.httpBody)) as! [String: Any]
        XCTAssertEqual(body["system"] as? String, "System text")
    }

}

// MARK: - AnthropicProvider request building

final class AnthropicProviderRequestTests: XCTestCase {

    func testUsesXApiKeyHeader() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
    }

    func testSetsAnthropicVersionHeader() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertNotNil(urlRequest.value(forHTTPHeaderField: "anthropic-version"))
    }

    func testNoAuthorizationHeader() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"),
                     "Anthropic uses x-api-key, not Authorization: Bearer")
    }

    func testBuildRequestURLPointsToMessages() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertTrue(urlRequest.url?.path.hasSuffix("messages") ?? false)
    }
}
