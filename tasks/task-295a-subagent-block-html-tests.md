# Task 295a — Subagent Block HTML Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit B2 of the wiring plan. Task 294 complete (RAG sources HTML).

The engine emits `.subagentStarted`/`.subagentUpdate` events; `ChatViewModel.applyEngineEvent`
creates a `SubagentBlockViewModel` in `subagentVMs` and a `ChatEntry` with `subagentID`,
but `ConversationHTMLRenderer` ignores `subagentID` and `SubagentBlockView` is never
rendered. The chat is HTML, so subagent activity is rendered in the renderer.

New surface in task 295b:
  - `SubagentBlock` — a `Sendable, Equatable` value snapshot of a subagent's state
    (`agentName`, `status`, tool lines, `summary`, `text`).
  - `ChatEntry.subagentBlock: SubagentBlock?`.
  - `ChatViewModel.applyEngineEvent` populates `subagentBlock` on subagent events.
  - `ConversationHTMLRenderer` renders a `subagent-block` for an entry with a `subagentBlock`.

TDD coverage:
  `MerlinTests/Unit/SubagentBlockHTMLTests.swift` — (1) `messageHTML` renders a
  `subagent-block` for an entry whose `subagentBlock` is set; (2) `ChatViewModel`
  populates `subagentBlock.text` after a `.subagentUpdate(.messageChunk)`.

## Write to: MerlinTests/Unit/SubagentBlockHTMLTests.swift

```swift
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
```

NOTE for executor: confirm the `AgentEvent` case labels — `.subagentStarted(id:agentName:)`
and `.subagentUpdate(id:event:)` — against `Merlin/Engine/` and adjust the calls to match
the real enum.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/SubagentBlockHTMLTests 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD FAILED — `SubagentBlock`, `SubagentToolLine`, `ChatEntry.subagentBlock`
do not exist yet.

## Commit
```
git add MerlinTests/Unit/SubagentBlockHTMLTests.swift tasks/task-295a-subagent-block-html-tests.md
git commit -m "Task 295a — Subagent block HTML tests (failing)"
```
