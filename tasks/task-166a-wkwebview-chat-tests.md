# Task 166a — WKWebView Chat Renderer Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 165b complete: DPO pair persistence.

SwiftUI `Text`-per-message cannot share a selection context across view boundaries —
cross-message drag selection is architecturally impossible. The fix is a single
`WKWebView` rendering the entire conversation as one HTML document. This task
writes the failing tests for the pure-Swift HTML generation layer, which can be
exercised without a live WKWebView instance.

New surface introduced in task 166b:

- `ConversationHTMLRenderer.render(_:)` — builds a full HTML document from `[ChatEntry]`
- `ConversationHTMLRenderer.messageHTML(for:)` — renders one `ChatEntry` as an HTML fragment
- `ConversationHTMLRenderer.chunkHTML(for:)` — minimal fragment for streaming append via JS
- `ConversationHTMLRenderer.htmlEscape(_:)` — escapes `< > & " '` for safe HTML embedding
- `ConversationHTMLRenderer.markdownToHTML(_:)` — converts fenced code blocks to `<pre><code>`,
  inline `**bold**`/`*italic*`/`` `code` `` to HTML; leaves prose as-is

TDD coverage:
  File — ConversationHTMLRendererTests: full HTML structure, per-role rendering,
         code block conversion, HTML escaping, image data URI handling, streaming chunks

---

## Write to: MerlinTests/Unit/ConversationHTMLRendererTests.swift

```swift
import XCTest
@testable import Merlin

final class ConversationHTMLRendererTests: XCTestCase {

    // MARK: – Document structure

    func testRenderEmptyProducesValidHTMLDocument() {
        let html = ConversationHTMLRenderer.render([])
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"), "must start with doctype")
        XCTAssertTrue(html.contains("<html"), "must contain <html>")
        XCTAssertTrue(html.contains("</html>"), "must close <html>")
        XCTAssertTrue(html.contains("<div id=\"messages\">"), "must contain messages container")
    }

    func testRenderContainsCSSVariables() {
        let html = ConversationHTMLRenderer.render([])
        XCTAssertTrue(html.contains("--bg:"), "must define --bg CSS variable")
        XCTAssertTrue(html.contains("--fg:"), "must define --fg CSS variable")
        XCTAssertTrue(html.contains("--bubble-user:"), "must define --bubble-user")
        XCTAssertTrue(html.contains("--bubble-assistant:"), "must define --bubble-assistant")
        XCTAssertTrue(html.contains("prefers-color-scheme: light"), "must have light mode overrides")
    }

    func testRenderContainsMerlinJSBridge() {
        let html = ConversationHTMLRenderer.render([])
        XCTAssertTrue(html.contains("const merlin ="), "must define merlin JS object")
        XCTAssertTrue(html.contains("appendChunk"), "must expose appendChunk function")
        XCTAssertTrue(html.contains("scrollToBottom"), "must expose scrollToBottom function")
        XCTAssertTrue(html.contains("merlinBridge"), "must post to merlinBridge message handler")
    }

    // MARK: – User messages

    func testUserMessageHasCorrectClass() {
        let entry = ChatEntry(role: .user, text: "Hello")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("class=\"message user\""), "user message must have .user class")
    }

    func testUserMessageTextAppears() {
        let entry = ChatEntry(role: .user, text: "What is 2+2?")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("What is 2+2?"))
    }

    func testUserMessageDataIDPresent() {
        let entry = ChatEntry(role: .user, text: "Hi")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("data-id=\"\(entry.id)\""), "must embed entry UUID as data-id")
    }

    // MARK: – Assistant messages

    func testAssistantMessageHasCorrectClass() {
        let entry = ChatEntry(role: .assistant, text: "I can help.")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("class=\"message assistant\""))
    }

    func testAssistantMessageTextAppears() {
        let entry = ChatEntry(role: .assistant, text: "Sure, let me explain.")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("Sure, let me explain."))
    }

    // MARK: – Thinking blocks

    func testThinkingBlockRenderedWhenPresent() {
        var entry = ChatEntry(role: .assistant, text: "The answer is 42.")
        entry.thinkingText = "Let me reason through this carefully."
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("thinking"), "thinking block must be present")
        XCTAssertTrue(html.contains("Let me reason through this carefully."))
    }

    func testThinkingBlockAbsentWhenEmpty() {
        let entry = ChatEntry(role: .assistant, text: "Direct answer.")
        let html = ConversationHTMLRenderer.render([entry])
        // No thinking section when thinkingText is empty
        XCTAssertFalse(html.contains("class=\"thinking\""))
    }

    func testThinkingToggleButtonPresent() {
        var entry = ChatEntry(role: .assistant, text: "Answer.")
        entry.thinkingText = "Reasoning."
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("toggleThinking"), "must emit toggleThinking JS call in button")
    }

    // MARK: – Tool calls

    func testToolCallHasCorrectClass() {
        var entry = ChatEntry(role: .tool, text: "")
        entry.toolName = "read_file"
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("class=\"message tool\""))
    }

    func testToolNameAppears() {
        var entry = ChatEntry(role: .tool, text: "")
        entry.toolName = "shell_exec"
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("shell_exec"))
    }

    func testToolResultAppears() {
        var entry = ChatEntry(role: .tool, text: "")
        entry.toolName = "read_file"
        entry.toolResult = "file contents here"
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("file contents here"))
    }

    func testToolArgumentsAppear() {
        var entry = ChatEntry(role: .tool, text: "")
        entry.toolName = "write_file"
        entry.toolArguments = "{\"path\": \"/tmp/out.txt\"}"
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("/tmp/out.txt"))
    }

    func testToolErrorClassApplied() {
        var entry = ChatEntry(role: .tool, text: "")
        entry.toolName = "bad_tool"
        entry.toolIsError = true
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("tool-error"), "error tool calls must have tool-error class")
    }

    func testToolToggleButtonPresent() {
        var entry = ChatEntry(role: .tool, text: "")
        entry.toolName = "list_dir"
        entry.toolResult = "a, b, c"
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("toggleTool"), "must emit toggleTool JS call in button")
    }

    // MARK: – System / error notes

    func testSystemNoteHasCorrectClass() {
        let entry = ChatEntry(role: .system, text: "Session started.")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("class=\"message system\""))
    }

    func testErrorNoteHasCorrectClass() {
        let entry = ChatEntry(role: .error, text: "Provider timeout.")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("class=\"message error\""))
    }

    // MARK: – HTML escaping

    func testXSSInUserTextIsEscaped() {
        let entry = ChatEntry(role: .user, text: "<script>alert('xss')</script>")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertFalse(html.contains("<script>alert"), "raw <script> must not appear")
        XCTAssertTrue(html.contains("&lt;script&gt;"), "< must be escaped to &lt;")
    }

    func testAmpersandEscaped() {
        let entry = ChatEntry(role: .user, text: "Tom & Jerry")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("Tom &amp; Jerry"))
    }

    func testQuoteEscapedInAttributes() {
        // Ensure double-quotes inside data attributes don't break HTML structure
        let entry = ChatEntry(role: .user, text: "Say \"hello\"")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertFalse(html.contains("=\"Say \"hello\"\""),
                       "unescaped quotes must not appear inside attribute values")
    }

    func testHtmlEscapeStandaloneFunction() {
        XCTAssertEqual(ConversationHTMLRenderer.htmlEscape("<b>hi</b>"), "&lt;b&gt;hi&lt;/b&gt;")
        XCTAssertEqual(ConversationHTMLRenderer.htmlEscape("a & b"), "a &amp; b")
        XCTAssertEqual(ConversationHTMLRenderer.htmlEscape("\"quoted\""), "&quot;quoted&quot;")
        XCTAssertEqual(ConversationHTMLRenderer.htmlEscape("plain"), "plain")
    }

    // MARK: – Markdown → HTML

    func testFencedCodeBlockConverted() {
        let entry = ChatEntry(role: .assistant, text: "```swift\nlet x = 1\n```")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("<pre><code"), "fenced block must become <pre><code>")
        XCTAssertTrue(html.contains("let x = 1"))
        XCTAssertFalse(html.contains("```"), "backtick fences must not appear in output")
    }

    func testLanguageTagAddedToCodeBlock() {
        let entry = ChatEntry(role: .assistant, text: "```python\nprint('hi')\n```")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("language-python") || html.contains("class=\"python\""),
                      "language tag must be present on code element")
    }

    func testInlineCodeConverted() {
        let entry = ChatEntry(role: .assistant, text: "Use `let` for constants.")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("<code>let</code>"))
    }

    func testBoldConverted() {
        let entry = ChatEntry(role: .assistant, text: "This is **important**.")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("<strong>important</strong>"))
    }

    func testItalicConverted() {
        let entry = ChatEntry(role: .assistant, text: "This is *emphasis*.")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("<em>emphasis</em>"))
    }

    func testMarkdownToHTMLStandaloneFunction() {
        let result = ConversationHTMLRenderer.markdownToHTML("**bold** and `code`")
        XCTAssertTrue(result.contains("<strong>bold</strong>"))
        XCTAssertTrue(result.contains("<code>code</code>"))
    }

    // MARK: – Image rendering

    func testBase64ImageDataURIBecomesImgTag() {
        let base64 = "data:image/png;base64,iVBORw0KGgo="
        let entry = ChatEntry(role: .assistant, text: "Here: ![](\(base64))")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("<img"), "base64 image markdown must become <img> tag")
        XCTAssertTrue(html.contains("data:image/png;base64,iVBORw0KGgo="),
                      "base64 data URI must be preserved")
    }

    func testRemoteImageURLBecomesImgTag() {
        let entry = ChatEntry(role: .assistant, text: "![photo](https://example.com/img.png)")
        let html = ConversationHTMLRenderer.render([entry])
        XCTAssertTrue(html.contains("<img"))
        XCTAssertTrue(html.contains("https://example.com/img.png"))
    }

    // MARK: – Streaming chunk

    func testChunkHTMLIsNonEmpty() {
        let entry = ChatEntry(role: .assistant, text: "partial response so far")
        let chunk = ConversationHTMLRenderer.chunkHTML(for: entry)
        XCTAssertFalse(chunk.isEmpty, "chunkHTML must return non-empty fragment")
    }

    func testChunkHTMLContainsText() {
        let entry = ChatEntry(role: .assistant, text: "streaming text")
        let chunk = ConversationHTMLRenderer.chunkHTML(for: entry)
        XCTAssertTrue(chunk.contains("streaming text"))
    }

    func testChunkHTMLContainsDataID() {
        let entry = ChatEntry(role: .assistant, text: "hello")
        let chunk = ConversationHTMLRenderer.chunkHTML(for: entry)
        XCTAssertTrue(chunk.contains(entry.id.uuidString),
                      "chunkHTML must contain entry UUID for JS targeting")
    }

    // MARK: – Multiple entries ordering

    func testMultipleEntriesRenderInOrder() {
        let e1 = ChatEntry(role: .user, text: "First")
        let e2 = ChatEntry(role: .assistant, text: "Second")
        let e3 = ChatEntry(role: .user, text: "Third")
        let html = ConversationHTMLRenderer.render([e1, e2, e3])
        let r1 = html.range(of: "First")!
        let r2 = html.range(of: "Second")!
        let r3 = html.range(of: "Third")!
        XCTAssertTrue(r1.lowerBound < r2.lowerBound && r2.lowerBound < r3.lowerBound,
                      "entries must appear in order")
    }

    func testMessageHTMLStandaloneFunction() {
        let entry = ChatEntry(role: .user, text: "standalone")
        let fragment = ConversationHTMLRenderer.messageHTML(for: entry)
        XCTAssertTrue(fragment.contains("standalone"))
        XCTAssertTrue(fragment.contains("user"))
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: **BUILD FAILED** with errors referencing missing `ConversationHTMLRenderer` type.
The test file itself must compile structurally — only the missing implementation causes failure.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ConversationHTMLRendererTests.swift \
        tasks/task-166a-wkwebview-chat-tests.md
git commit -m "Task 166a — ConversationHTMLRendererTests (failing)"
```
