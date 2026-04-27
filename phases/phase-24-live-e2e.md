# Phase 24 — Live Provider Tests + Full E2E

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All components complete. This is the final integration phase.

---

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

---

## Write to: MerlinE2ETests/AgenticLoopE2ETests.swift

```swift
import XCTest
@testable import Merlin

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

---

## Verify

Run the full unit + integration test suite (no env vars needed):
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' 2>&1 | grep -E 'passed|failed|error:|BUILD|Test Suite'
```

Expected: all unit + integration tests pass. Zero errors.

Verify live tests skip cleanly without credentials:
```bash
xcodebuild -scheme MerlinTests-Live test-without-building -destination 'platform=macOS' \
    -only-testing:MerlinLiveTests/DeepSeekProviderLiveTests \
    -only-testing:MerlinE2ETests/AgenticLoopE2ETests 2>&1 | grep -E 'skipped|passed|failed'
```

Expected: all live/E2E tests skip cleanly.

Final zero-warning build:
```bash
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'warning:|error:|BUILD'
```

Expected: `BUILD SUCCEEDED` with zero errors and zero warnings.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinLiveTests/DeepSeekProviderLiveTests.swift \
    MerlinE2ETests/AgenticLoopE2ETests.swift
git commit -m "Phase 24 — Live provider tests + full E2E loop"
```

---

## Final acceptance checklist

- [ ] `xcodebuild -scheme MerlinTests` — all unit + integration tests pass
- [ ] `swift build` / `xcodebuild` — zero errors, zero warnings with SWIFT_STRICT_CONCURRENCY=complete
- [ ] App launches, first-launch setup appears if no Keychain key
- [ ] Sending a message streams response in ChatView
- [ ] Tool call card expands/collapses in ChatView
- [ ] Auth popup appears for unknown tool, remembers pattern correctly
- [ ] VisualLayoutTests — no clipping, accessibility audit passes
- [ ] With `RUN_LIVE_TESTS=1` + `DEEPSEEK_API_KEY`: full agentic loop reads real file via DeepSeek tool call
- [ ] With `RUN_LIVE_TESTS=1` + Accessibility granted: AX click test passes on TestTargetApp
- [ ] With `RUN_LIVE_TESTS=1` + LM Studio running with Qwen2.5-VL-72B loaded: vision query identifies UI element
