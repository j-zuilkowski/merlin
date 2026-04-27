import XCTest
@testable import Merlin

final class OpenAICompatibleProviderTests: XCTestCase {

    private let deepseekURL = URL(string: "https://api.deepseek.com/v1")!
    private let ollamaURL = URL(string: "http://localhost:11434/v1")!

    func testBuildRequestSetsAuthHeader() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        let req = CompletionRequest(model: "deepseek-chat", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testBuildRequestNoAuthHeaderWhenNilKey() throws {
        let provider = OpenAICompatibleProvider(
            id: "ollama", baseURL: ollamaURL, apiKey: nil, modelID: "llama3")
        let req = CompletionRequest(model: "llama3", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))
    }

    func testBuildRequestBodyContainsModel() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        // Empty model string — provider falls back to its configured modelID
        let req = CompletionRequest(model: "", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        let body = try JSONSerialization.jsonObject(with: urlRequest.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "deepseek-chat")
    }

    func testBuildRequestBodyIncludesThinking() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        let thinking = ThinkingConfig(type: "enabled", reasoningEffort: "high")
        let req = CompletionRequest(
            model: "deepseek-chat", messages: [], tools: nil, thinking: thinking)
        let urlRequest = try provider.buildRequest(req)
        let body = try JSONSerialization.jsonObject(with: urlRequest.httpBody!) as! [String: Any]
        XCTAssertNotNil(body["thinking"])
    }

    func testBuildRequestURLEndsInChatCompletions() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        let req = CompletionRequest(model: "deepseek-chat", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertTrue(urlRequest.url?.path.hasSuffix("chat/completions") ?? false)
    }

    func testBuildRequestSetsContentTypeJSON() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        let req = CompletionRequest(model: "deepseek-chat", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
