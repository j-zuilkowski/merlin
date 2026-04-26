# Phase 17a — AgenticEngine Tests

Context: HANDOFF.md. All engine components exist. Write failing tests using mock provider.

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
        let engine = makeEngine(provider: provider)
        var collected = ""
        for await event in engine.send(userMessage: "hi") {
            if case .text(let t) = event { collected += t }
        }
        XCTAssertEqual(collected, "hello world")
    }

    // Engine executes tool call and loops
    func testToolCallLoop() async throws {
        // First response: tool call. Second response: final text.
        let provider = MockProvider(responses: [
            MockResponse.toolCall(id: "tc1", name: "echo_tool", args: #"{"value":"ping"}"#),
            MockResponse.text("pong received"),
        ])
        let engine = makeEngine(provider: provider)
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
        let engine = makeEngine(proProvider: pro, flashProvider: flash)
        _ = engine.send(userMessage: "read the file at /tmp/test.txt")
        XCTAssertTrue(flash.wasUsed)
        XCTAssertFalse(pro.wasUsed)
    }

    // Engine appends compaction note when context manager compacts
    func testContextCompactionNoteAppears() async throws {
        let engine = makeEngine(provider: MockProvider(chunks: [
            .init(delta: .init(content: "ok"), finishReason: "stop")
        ]))
        // Force compaction by filling context
        engine.contextManager.forceCompaction()
        var events: [AgentEvent] = []
        for await e in engine.send(userMessage: "hi") { events.append(e) }
        XCTAssertTrue(events.contains { if case .systemNote(let n) = $0 { return n.contains("compacted") } ; return false })
    }
}
```

## Acceptance
- [ ] Compiles (types missing — expected)
