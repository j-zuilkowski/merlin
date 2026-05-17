# Phase 329 — Eval Render Harness (S10 chat rendering)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 328 complete: surface harness landed.

W5 — the **M3 render harness** for scenario **S10** (chat rendering kinds).
`ConversationHTMLRenderer` is a pure `[ChatEntry] -> String` function, so every render
kind is asserted directly with no app run — these are fast unit tests in `MerlinTests`.
Covers every `ChatEntry` render path: the four message roles, HTML-escaping / injection
safety, the thinking block, tool-call rows (3 states), the subagent block, the RAG
sources block, and the grounding report.

API (verified): `ConversationHTMLRenderer.messageHTML(for: ChatEntry) -> String` and
`render([ChatEntry]) -> String` — `nonisolated static`, pure. `ChatEntry` and its field
types (`ToolCallEntry`, `SubagentBlock`/`SubagentToolLine`, `RAGChunk`, `GroundingReport`)
all have memberwise/explicit inits.

---

## Write to: MerlinTests/Unit/ConversationRenderTests.swift

```swift
import XCTest
@testable import Merlin

/// S10 — chat rendering. Asserts `ConversationHTMLRenderer` output for every ChatEntry
/// kind: structure, content, and — critically — HTML escaping (no injection).
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
                           "\(role) content must be escaped — no live <script> tag")
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
                          result: nil,  isError: false),
            ToolCallEntry(id: "2", name: "DONE_TOOL",    arguments: "{}",
                          result: "ok", isError: false),
            ToolCallEntry(id: "3", name: "ERROR_TOOL",   arguments: "{}",
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
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/ConversationRenderTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:|warning:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, zero warnings; all `ConversationRenderTests` pass. If a
content-marker assertion fails, the renderer dropped that kind — a finding. If
`testMessageContentIsHTMLEscaped` fails, that is a security finding (top priority).

> If `ChatEntry` / `RAGChunk` / `GroundingReport` initialiser labels differ from the
> above, adjust the call sites to the real signatures — the assertions stay the same.

## Commit
```
git add MerlinTests/Unit/ConversationRenderTests.swift phases/phase-329-eval-render-harness.md
git commit -m "Phase 329 — Eval render harness (S10 chat rendering)"
```
