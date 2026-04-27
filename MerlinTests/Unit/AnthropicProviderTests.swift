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
