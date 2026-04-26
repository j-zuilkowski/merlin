# Phase 24 — Live Provider Tests + Full E2E

Context: HANDOFF.md. All components complete. Final integration verification.

## Write to: MerlinLiveTests/DeepSeekProviderLiveTests.swift

```swift
import XCTest
@testable import Merlin

final class DeepSeekProviderLiveTests: XCTestCase {

    var provider: DeepSeekProvider!

    override func setUp() throws {
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
              ?? KeychainManager.readAPIKey()
        else { throw XCTSkip("No DeepSeek API key") }
        provider = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
    }

    func testSimpleCompletion() async throws {
        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [Message(role: .user, content: .text("Reply with only the word: PONG"), timestamp: Date())]
        )
        var result = ""
        for try await chunk in try await provider.complete(request: req) {
            result += chunk.delta?.content ?? ""
        }
        XCTAssertTrue(result.uppercased().contains("PONG"))
    }

    func testToolCallRoundTrip() async throws {
        // Write a file for the agent to find
        try "test content".write(toFile: "/tmp/merlin-test.txt", atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: "/tmp/merlin-test.txt") }

        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [Message(role: .user, content: .text("Read the file at /tmp/merlin-test.txt"), timestamp: Date())],
            tools: [ToolDefinitions.readFile]
        )
        // Reassemble tool calls from streaming deltas by index
        // Deltas arrive as partial chunks: first chunk has id+name, subsequent have argument fragments
        var assembled: [Int: (id: String, name: String, args: String)] = [:]
        var finishReason: String?
        for try await chunk in try await provider.complete(request: req) {
            finishReason = chunk.finishReason ?? finishReason
            for delta in chunk.delta?.toolCalls ?? [] {
                var entry = assembled[delta.index] ?? (id: delta.id ?? "", name: "", args: "")
                if let n = delta.function?.name, !n.isEmpty { entry.name = n }
                if let id = delta.id, !id.isEmpty { entry.id = id }
                entry.args += delta.function?.arguments ?? ""
                assembled[delta.index] = entry
            }
        }
        XCTAssertEqual(finishReason, "tool_calls")
        XCTAssertTrue(assembled.values.contains { $0.name == "read_file" },
                      "Model should have requested read_file, got: \(assembled)")
    }

    func testThinkingModeActivates() async throws {
        let req = CompletionRequest(
            model: "deepseek-v4-pro",
            messages: [Message(role: .user, content: .text("Why is 2+2=4?"), timestamp: Date())],
            thinking: ThinkingConfig(type: "enabled", reasoningEffort: "high")
        )
        let pro = DeepSeekProvider(apiKey: provider.apiKey, model: "deepseek-v4-pro")
        var hasThinking = false
        for try await chunk in try await pro.complete(request: req) {
            if chunk.delta?.thinkingContent != nil { hasThinking = true }
        }
        XCTAssertTrue(hasThinking)
    }
}
```

## Write to: MerlinE2ETests/AgenticLoopE2ETests.swift

```swift
final class AgenticLoopE2ETests: XCTestCase {

    func testFullLoopWithRealDeepSeek() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil,
              let key = KeychainManager.readAPIKey()
        else { throw XCTSkip("Live tests disabled or no API key") }

        // Create a temp file for the agent to read
        let tmpPath = "/tmp/merlin-e2e-test.txt"
        try "hello from e2e test".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "read_file", pattern: "/tmp/**")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        router.register(name: "read_file") { args in
            let decoded = try JSONDecoder().decode([String: String].self, from: args.data(using: .utf8)!)
            return try await FileSystemTools.readFile(path: decoded["path"]!)
        }

        let pro = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
        let engine = AgenticEngine(
            proProvider: pro, flashProvider: pro,
            visionProvider: LMStudioProvider(),
            toolRouter: router,
            contextManager: ContextManager()
        )

        var finalText = ""
        for await event in engine.send(userMessage: "Read \(tmpPath) and tell me what it says") {
            if case .text(let t) = event { finalText += t }
        }
        XCTAssertTrue(finalText.lowercased().contains("hello from e2e test"))
    }
}
```

## Xcode Test Schemes

Create two test schemes (document in README):
- **MerlinTests** (default): runs `MerlinTests` target only. No env vars needed.
- **MerlinTests-Live**: runs all three test targets. Set env vars:
  - `RUN_LIVE_TESTS = 1`
  - `DEEPSEEK_API_KEY = <key>` (or read from Keychain)

## Final Acceptance Checklist
- [ ] `swift test` (MerlinTests only) — all unit + integration tests pass
- [ ] `swift build` — zero errors, zero warnings
- [ ] App launches, first-launch setup appears if no Keychain key
- [ ] Sending a message to DeepSeek streams response in ChatView
- [ ] Tool call card expands/collapses in ChatView
- [ ] Auth popup appears for unknown tool, remembers pattern correctly
- [ ] VisualLayoutTests — no clipping, accessibility audit passes
- [ ] With `RUN_LIVE_TESTS=1`: full agentic loop reads real file via DeepSeek tool call
- [ ] With `RUN_LIVE_TESTS=1` + Accessibility granted: AX click test passes on TestTargetApp
