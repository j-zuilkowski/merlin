import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineTests: XCTestCase {

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

    func testToolCallLoop() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "tc1", name: "echo_tool", args: #"{"value":"ping"}"#),
            MockLLMResponse.text("pong received"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("echo_tool") { args in
            let data = args.data(using: .utf8)!
            let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
            return json["value"] ?? ""
        }

        var finalText = ""
        for await event in engine.send(userMessage: "call echo") {
            if case .text(let t) = event { finalText += t }
        }
        XCTAssertTrue(finalText.contains("pong received"))
    }

    func testProviderSelectionFlash() async throws {
        let flash = MockProvider(chunks: [.init(delta: .init(content: "ok"), finishReason: "stop")])
        flash.id_ = "deepseek-v4-flash"
        let pro = MockProvider(chunks: [])
        pro.id_ = "deepseek-v4-pro"
        let engine = makeEngine(proProvider: pro, flashProvider: flash)
        for await _ in engine.send(userMessage: "read the file at /tmp/test.txt") {}
        XCTAssertTrue(flash.wasUsed)
        XCTAssertFalse(pro.wasUsed)
    }

    func testContextCompactionNoteAppears() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "tc1", name: "inflate_tool", args: #"{"value":"go"}"#),
            MockLLMResponse.text("done"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("inflate_tool") { _ in
            String(repeating: "z", count: 3_000_000)
        }

        for _ in 0..<97 {
            engine.contextManager.append(Message(
                role: .tool,
                content: .text(String(repeating: "y", count: 28_000)),
                toolCallId: "seed",
                timestamp: Date()
            ))
        }

        var events: [AgentEvent] = []
        for await e in engine.send(userMessage: "trigger compaction") {
            events.append(e)
        }
        XCTAssertTrue(events.contains {
            if case .systemNote(let note) = $0 { return note.contains("compacted") }
            return false
        })
    }
}
