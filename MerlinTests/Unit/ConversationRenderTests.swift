import XCTest
@testable import Merlin

/// S10 - chat rendering. Asserts `ConversationHTMLRenderer` output for every ChatEntry
/// kind: structure, content, and - critically - HTML escaping (no injection).
final class ConversationRenderTests: XCTestCase {

    // MARK: - Message roles

    func testUserMessageRendersWithUserClass() {
        let html = ConversationHTMLRenderer.messageHTML(
            for: ChatEntry(role: .user, text: "hello"))
        XCTAssertTrue(html.contains("message user"))
        XCTAssertTrue(html.contains("hello"))
    }

    func testAssistantMessageRendersWithAssistantClass() {
        let html = ConversationHTMLRenderer.messageHTML(
            for: ChatEntry(role: .assistant, text: "hi there"))
        XCTAssertTrue(html.contains("message assistant"))
        XCTAssertTrue(html.contains("hi there"))
    }

    func testSystemMessageRendersWithSystemClass() {
        let html = ConversationHTMLRenderer.messageHTML(
            for: ChatEntry(role: .system, text: "system note"))
        XCTAssertTrue(html.contains("message system"))
    }

    func testErrorMessageRendersWithErrorClass() {
        let html = ConversationHTMLRenderer.messageHTML(
            for: ChatEntry(role: .error, text: "boom"))
        XCTAssertTrue(html.contains("message error"))
    }

    // MARK: - Injection safety (gating)

    func testMessageContentIsHTMLEscaped() {
        let payload = "<script>alert('xss')</script>"
        for role in [ChatEntry.Role.user, .system, .error] {
            let html = ConversationHTMLRenderer.messageHTML(
                for: ChatEntry(role: role, text: payload))
            XCTAssertFalse(html.contains("<script>"),
                           "\(role) content must be escaped - no live <script> tag")
            XCTAssertTrue(html.contains("&lt;script&gt;"),
                          "\(role) content must appear as escaped entities")
        }
    }

    // MARK: - Thinking block

    func testThinkingBlockRendersWhenPresent() {
        let entry = ChatEntry(role: .assistant, text: "answer",
                              thinkingText: "UNIQUE_THOUGHT_MARKER",
                              thinkingExpanded: true)
        let html = ConversationHTMLRenderer.messageHTML(for: entry)
        XCTAssertTrue(html.contains("UNIQUE_THOUGHT_MARKER"),
                      "an assistant entry with thinkingText must render the thinking block")
    }

    // MARK: - Tool-call rows (running / done / error)

    func testToolCallRowsRenderForEachState() {
        let calls = [
            ToolCallEntry(id: "1", name: "RUNNING_TOOL", arguments: "{}",
                          result: nil, isError: false),
            ToolCallEntry(id: "2", name: "DONE_TOOL", arguments: "{}",
                          result: "ok", isError: false),
            ToolCallEntry(id: "3", name: "ERROR_TOOL", arguments: "{}",
                          result: "failed", isError: true),
        ]
        let html = ConversationHTMLRenderer.messageHTML(
            for: ChatEntry(role: .assistant, text: "", toolCalls: calls))
        XCTAssertTrue(html.contains("RUNNING_TOOL"))
        XCTAssertTrue(html.contains("DONE_TOOL"))
        XCTAssertTrue(html.contains("ERROR_TOOL"))
    }

    // MARK: - Subagent block

    func testSubagentBlockRendersWhenPresent() {
        let block = SubagentBlock(
            agentName: "UNIQUE_AGENT_MARKER", status: "completed",
            tools: [SubagentToolLine(name: "read_file", done: true)],
            summary: "done", text: "subagent ran")
        let html = ConversationHTMLRenderer.messageHTML(
            for: ChatEntry(role: .assistant, text: "", subagentBlock: block))
        XCTAssertTrue(html.contains("UNIQUE_AGENT_MARKER"),
                      "an entry with a subagentBlock must render it")
    }

    // MARK: - RAG sources block

    func testRAGSourcesBlockRendersWhenPresent() {
        let chunk = RAGChunk(
            chunkID: "c1", source: "books", bookID: "b1",
            bookTitle: "UNIQUE_BOOK_MARKER", headingPath: "Chapter 1",
            chunkType: "paragraph", text: "retrieved text",
            wordCount: 2, bm25Score: nil, cosineScore: nil,
            rrfScore: 0.9, rerankScore: nil)
        let html = ConversationHTMLRenderer.messageHTML(
            for: ChatEntry(role: .assistant, text: "grounded answer", ragSources: [chunk]))
        XCTAssertTrue(html.contains("UNIQUE_BOOK_MARKER"),
                      "an entry with ragSources must render the sources block")
    }

    // MARK: - Grounding report

    func testGroundingReportRendersWhenPresent() {
        let report = GroundingReport(
            totalChunks: 3, memoryChunks: 1, bookChunks: 2, averageScore: 0.82,
            oldestMemoryAgeDays: 4, hasStaleMemory: false, isWellGrounded: true)
        let html = ConversationHTMLRenderer.messageHTML(
            for: ChatEntry(role: .assistant, text: "answer", groundingReport: report))
        XCTAssertFalse(html.isEmpty)
        XCTAssertTrue(html.contains("3") || html.lowercased().contains("ground"),
                      "an entry with a groundingReport must render grounding detail")
    }

    // MARK: - Whole conversation

    func testRenderProducesADocumentForAMixedConversation() {
        let entries = [
            ChatEntry(role: .user, text: "question"),
            ChatEntry(role: .assistant, text: "answer"),
            ChatEntry(role: .system, text: "note"),
            ChatEntry(role: .error, text: "oops"),
        ]
        let html = ConversationHTMLRenderer.render(entries)
        XCTAssertTrue(html.contains("message user"))
        XCTAssertTrue(html.contains("message assistant"))
        XCTAssertTrue(html.contains("message system"))
        XCTAssertTrue(html.contains("message error"))
    }
}
