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
}
