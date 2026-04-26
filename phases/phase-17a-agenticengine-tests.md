# Phase 17a — AgenticEngine Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All engine components exist: ContextManager (14b), ToolRouter (15), ThinkingModeDetector (16), providers (03b, 04).
TestHelpers/MockProvider.swift and TestHelpers/EngineFactory.swift are already written (phase 01 scaffold).
`MockProvider`, `MockLLMResponse`, `NullAuthPresenter`, `makeEngine` are available in the test targets.

---

## Write to: MerlinTests/Unit/AgenticEngineTests.swift

```swift
import XCTest
@testable import Merlin

final class AgenticEngineTests: XCTestCase {

    // Engine completes single turn with no tool calls
    func testSimpleTurn() async throws {
        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "hello world"), finishReason: nil),
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])
        let engine = await makeEngine(provider: provider)
        var collected = ""
        for await event in engine.send(userMessage: "hi") {
            if case .text(let t) = event { collected += t }
        }
        XCTAssertEqual(collected, "hello world")
    }

    // Engine executes tool call and loops
    func testToolCallLoop() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "tc1", name: "echo_tool", args: #"{"value":"ping"}"#),
            MockLLMResponse.text("pong received"),
        ])
        let engine = await makeEngine(provider: provider)
        engine.registerTool("echo_tool") { args in
            let d = args.data(using: .utf8)!
            let j = try JSONSerialization.jsonObject(with: d) as! [String: String]
            return j["value"] ?? ""
        }
        var finalText = ""
        for await event in engine.send(userMessage: "call echo") {
            if case .text(let t) = event { finalText += t }
        }
        XCTAssertTrue(finalText.contains("pong received"))
    }

    // Engine selects flash provider for mechanical tasks
    func testProviderSelectionFlash() async throws {
        let flash = MockProvider(chunks: [.init(delta: .init(content: "ok"), finishReason: "stop")])
        flash.id_ = "deepseek-v4-flash"
        let pro = MockProvider(chunks: [])
        pro.id_ = "deepseek-v4-pro"
        let engine = await makeEngine(proProvider: pro, flashProvider: flash)
        for await _ in engine.send(userMessage: "read the file at /tmp/test.txt") {}
        XCTAssertTrue(flash.wasUsed)
        XCTAssertFalse(pro.wasUsed)
    }

    // Engine appends compaction note when context manager compacts
    func testContextCompactionNoteAppears() async throws {
        let engine = await makeEngine(provider: MockProvider(chunks: [
            .init(delta: .init(content: "ok"), finishReason: "stop")
        ]))
        engine.contextManager.forceCompaction()
        var events: [AgentEvent] = []
        for await e in engine.send(userMessage: "hi") { events.append(e) }
        XCTAssertTrue(events.contains {
            if case .systemNote(let n) = $0 { return n.contains("compacted") }
            return false
        })
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing `AgenticEngine` and `AgentEvent`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `AgenticEngine` and `AgentEvent`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AgenticEngineTests.swift
git commit -m "Phase 17a — AgenticEngineTests (failing)"
```
