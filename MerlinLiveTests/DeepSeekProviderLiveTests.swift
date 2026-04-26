import Foundation
import XCTest
@testable import Merlin

final class DeepSeekProviderLiveTests: XCTestCase {
    var provider: DeepSeekProvider!

    override func setUpWithError() throws {
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
            ?? KeychainManager.readAPIKey()
        else {
            throw XCTSkip("No DeepSeek API key")
        }

        provider = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
    }

    func testSimpleCompletion() async throws {
        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [
                Message(
                    role: .user,
                    content: .text("Reply with only the word: PONG"),
                    timestamp: Date()
                )
            ]
        )

        var result = ""
        for try await chunk in try await provider.complete(request: req) {
            result += chunk.delta?.content ?? ""
        }

        XCTAssertTrue(result.uppercased().contains("PONG"))
    }

    func testToolCallRoundTrip() async throws {
        let path = "/tmp/merlin-test.txt"
        try "test content".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [
                Message(
                    role: .user,
                    content: .text("Use read_file to read \(path) and return the contents."),
                    timestamp: Date()
                )
            ],
            tools: [ToolDefinitions.readFile]
        )

        var assembled: [Int: (id: String, name: String, args: String)] = [:]
        var finishReason: String?

        for try await chunk in try await provider.complete(request: req) {
            finishReason = chunk.finishReason ?? finishReason
            for delta in chunk.delta?.toolCalls ?? [] {
                var entry = assembled[delta.index] ?? (id: delta.id ?? "", name: "", args: "")
                if let name = delta.function?.name, !name.isEmpty {
                    entry.name = name
                }
                if let id = delta.id, !id.isEmpty {
                    entry.id = id
                }
                entry.args += delta.function?.arguments ?? ""
                assembled[delta.index] = entry
            }
        }

        XCTAssertEqual(finishReason, "tool_calls")
        XCTAssertTrue(
            assembled.values.contains { $0.name == "read_file" },
            "Model should have requested read_file, got: \(assembled)"
        )
    }

    func testThinkingModeActivates() async throws {
        let req = CompletionRequest(
            model: "deepseek-v4-pro",
            messages: [
                Message(
                    role: .user,
                    content: .text("Why is 2+2=4?"),
                    timestamp: Date()
                )
            ],
            thinking: ThinkingConfig(type: "enabled", reasoningEffort: "high")
        )
        let pro = DeepSeekProvider(apiKey: provider.apiKey, model: "deepseek-v4-pro")

        var hasThinking = false
        for try await chunk in try await pro.complete(request: req) {
            if chunk.delta?.thinkingContent != nil {
                hasThinking = true
            }
        }

        XCTAssertTrue(hasThinking)
    }
}
