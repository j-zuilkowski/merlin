import XCTest
@testable import Merlin

/// Task 295a — failing tests for subagent-block HTML rendering + ChatViewModel wiring.
@MainActor
final class SubagentBlockHTMLTests: XCTestCase {

    func testRendererEmitsSubagentBlockForEntryWithSubagentBlock() {
        var entry = ChatEntry(role: .assistant, text: "")
        entry.subagentID = UUID()
        entry.subagentBlock = SubagentBlock(
            agentName: "explorer",
            status: "running",
            tools: [SubagentToolLine(name: "grep", done: true)],
            summary: nil,
            text: "investigating")
        let html = ConversationHTMLRenderer.messageHTML(for: entry)
        XCTAssertTrue(html.contains("subagent-block"),
                      "an entry with a subagentBlock must render a subagent-block")
        XCTAssertTrue(html.contains("explorer"), "the agent name must appear")
        XCTAssertTrue(html.contains("grep"), "tool lines must appear")
    }

    func testChatViewModelPopulatesSubagentBlockOnUpdate() {
        let model = ChatViewModel()
        let id = UUID()
        model.applyEngineEvent(.subagentStarted(id: id, agentName: "explorer"))
        model.applyEngineEvent(.subagentUpdate(id: id, event: .messageChunk("hello")))
        let entry = model.items.first { $0.subagentID == id }
        XCTAssertEqual(entry?.subagentBlock?.text, "hello",
                       "ChatViewModel must mirror subagent state onto the ChatEntry")
    }
}
