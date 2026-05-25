import XCTest
@testable import Merlin

final class ProviderTests: XCTestCase {

    // DeepSeek builds correct URL
    func testDeepSeekBaseURL() {
        let p = DeepSeekProvider(apiKey: "test-key", model: "deepseek-v4-pro")
        XCTAssertEqual(p.baseURL.host, "api.deepseek.com")
        XCTAssertEqual(p.id, "deepseek-v4-pro")
    }

    // Local OpenAI-compatible provider uses localhost
    func testLocalOpenAICompatibleBaseURL() {
        let p = OpenAICompatibleProvider(
            id: "lmstudio",
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelID: "Qwen2.5-VL-72B-Instruct-Q4_K_M"
        )
        XCTAssertEqual(p.baseURL.host, "localhost")
        XCTAssertEqual(p.baseURL.port, 1234)
    }

    // Request serialiser includes thinking config when present
    func testRequestIncludesThinking() throws {
        let req = CompletionRequest(
            model: "deepseek-v4-pro",
            messages: [Message(role: .user, content: .text("hi"), timestamp: Date())],
            thinking: ThinkingConfig(type: "enabled", reasoningEffort: "high")
        )
        let p = DeepSeekProvider(apiKey: "k", model: "deepseek-v4-pro")
        let body = try p.buildRequestBody(req)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let thinking = json["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled")
    }

    // Request omits thinking when nil
    func testRequestOmitsThinkingWhenNil() throws {
        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [Message(role: .user, content: .text("hi"), timestamp: Date())]
        )
        let p = DeepSeekProvider(apiKey: "k", model: "deepseek-v4-flash")
        let body = try p.buildRequestBody(req)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertNil(json["thinking"])
    }

    // SSE line parser extracts delta content
    func testSSEParserExtractsDelta() throws {
        let line = #"data: {"id":"1","choices":[{"delta":{"content":"hello"},"finish_reason":null}]}"#
        let chunk = try SSEParser.parseChunk(line)
        XCTAssertEqual(chunk?.delta?.content, "hello")
    }

    // SSE parser returns nil for non-data lines
    func testSSEParserIgnoresComments() throws {
        XCTAssertNil(try SSEParser.parseChunk(": keep-alive"))
        XCTAssertNil(try SSEParser.parseChunk("data: [DONE]"))
    }

    func testRequestEncodesUnsafeToolNamesForOpenAIWireFormat() throws {
        let canonicalName = "mcp:kicad:route_board"
        let wireName = "__merlin_tool_name_encoded__mcp_u003A_kicad_u003A_route_board"
        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [
                Message(
                    role: .assistant,
                    content: .text(""),
                    toolCalls: [
                        ToolCall(
                            id: "call_1",
                            type: "function",
                            function: .init(name: canonicalName, arguments: #"{"net":"GND"}"#)
                        )
                    ],
                    timestamp: Date()
                )
            ],
            tools: [
                ToolDefinition(
                    function: .init(
                        name: canonicalName,
                        description: "Route a board.",
                        parameters: JSONSchema(type: "object")
                    )
                )
            ]
        )

        let data = try encodeRequest(
            req,
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            model: "deepseek-v4-flash"
        )
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let tools = json["tools"] as! [[String: Any]]
        let toolFunction = tools[0]["function"] as! [String: Any]
        XCTAssertEqual(toolFunction["name"] as? String, wireName)

        let messages = json["messages"] as! [[String: Any]]
        let toolCalls = messages[0]["tool_calls"] as! [[String: Any]]
        let callFunction = toolCalls[0]["function"] as! [String: Any]
        XCTAssertEqual(callFunction["name"] as? String, wireName)
    }

    func testSSEParserDecodesWireToolNameToCanonicalName() throws {
        let line = #"data: {"id":"1","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"__merlin_tool_name_encoded__mcp_u003A_kicad_u003A_route_board","arguments":"{}"}}]},"finish_reason":null}]}"#
        let chunk = try SSEParser.parseChunk(line)
        let function = chunk?.delta?.toolCalls?.first?.function
        XCTAssertEqual(function?.name, "mcp:kicad:route_board")
        XCTAssertEqual(function?.arguments, "{}")
    }

    func testSSEParserLeavesValidLookalikeToolNamesUnchanged() throws {
        let line = #"data: {"id":"1","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"mcp_u003A_kicad","arguments":"{}"}}]},"finish_reason":null}]}"#
        let chunk = try SSEParser.parseChunk(line)
        XCTAssertEqual(chunk?.delta?.toolCalls?.first?.function?.name, "mcp_u003A_kicad")
    }

    func testOpenAICompatibleProviderDoesNotEmitAnthropicCacheControl() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek",
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            apiKey: "sk-test",
            modelID: "deepseek-chat"
        )

        var req = CompletionRequest(model: "deepseek-chat", messages: [], tools: nil)
        req.cachePolicy = .ephemeral

        let urlRequest = try provider.buildRequest(req)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "anthropic-beta"))

        let bodyData = try XCTUnwrap(urlRequest.httpBody)
        let bodyText = String(data: bodyData, encoding: .utf8) ?? ""
        XCTAssertFalse(bodyText.contains("cache_control"))
    }

}
