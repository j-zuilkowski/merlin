# Phase 166b — WKWebView Chat Renderer

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 166a complete: ConversationHTMLRendererTests failing (missing implementation).

Migrate `ChatView`'s message list from SwiftUI `Text`-per-message to a single `WKWebView`.
SwiftUI `.textSelection(.enabled)` creates an isolated AppKit selection island per `Text`
view — cross-message drag selection is impossible regardless of container modifiers. A
single WKWebView renders the entire conversation as one HTML document; native browser
selection spans all messages. Claude desktop and OpenAI Codex use the same approach
(both are Electron apps backed by Chromium). See architecture.md `[v3] ChatView`.

---

## New file: `Merlin/Views/Chat/ConversationHTMLRenderer.swift`

```swift
import Foundation

/// Converts `[ChatEntry]` to HTML for display in `ConversationWebView`.
///
/// All methods are `nonisolated static` so they can be called from any context
/// without actor hopping. HTML generation is pure string transformation — no I/O.
enum ConversationHTMLRenderer {

    // MARK: - Public API

    /// Full HTML document for the entire conversation. Loaded once via
    /// `WKWebView.loadHTMLString(_:baseURL:)` then updated incrementally via JS.
    static func render(_ entries: [ChatEntry]) -> String {
        let body = entries.map { messageHTML(for: $0) }.joined(separator: "\n")
        return htmlDocument(body: body)
    }

    /// HTML fragment for a single entry. Used both in `render(_:)` and to inject
    /// new messages at runtime via `merlin.addMessage(html)`.
    static func messageHTML(for entry: ChatEntry) -> String {
        let id = entry.id.uuidString
        switch entry.role {
        case .user:
            return """
            <div class="message user" data-id="\(id)">\
            \(markdownToHTML(htmlEscape(entry.text)))</div>
            """
        case .assistant:
            let content = markdownToHTML(htmlEscape(entry.text))
            let thinking = entry.thinkingText.isEmpty ? "" : thinkingHTML(entry)
            return """
            <div class="message assistant" data-id="\(id)">\
            \(thinking)\(content)</div>
            """
        case .tool:
            return toolHTML(entry)
        case .system:
            return """
            <div class="message system" data-id="\(id)">\
            \(htmlEscape(entry.text))</div>
            """
        case .error:
            return """
            <div class="message error" data-id="\(id)">\
            \(htmlEscape(entry.text))</div>
            """
        }
    }

    /// Minimal HTML fragment for the streaming assistant message. Contains only
    /// the entry UUID and current text — no thinking block or tool rows. The
    /// JS `merlin.appendChunk(id, html)` call replaces the inner content of the
    /// in-progress bubble without a full re-render.
    static func chunkHTML(for entry: ChatEntry) -> String {
        let id = entry.id.uuidString
        let content = markdownToHTML(htmlEscape(entry.text))
        return """
        <div class="message assistant streaming" data-id="\(id)">\(content)</div>
        """
    }

    // MARK: - HTML escaping

    /// Escapes the five characters that are unsafe in HTML text nodes and attributes.
    static func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'",  with: "&#39;")
    }

    // MARK: - Markdown → HTML

    /// Converts a subset of Markdown to HTML:
    ///   - Fenced code blocks (``` lang … ```) → `<pre><code class="language-lang">…</code></pre>`
    ///   - Inline `code` → `<code>code</code>`
    ///   - **bold** → `<strong>bold</strong>`
    ///   - *italic* → `<em>italic</em>`
    ///   - ![alt](url) → `<img src="url" alt="alt">` (supports data: and https: URIs)
    ///   - Paragraph breaks (double newline) → `<p>` wrapping
    ///
    /// Input must already be HTML-escaped (entity references are preserved).
    /// Code block content is NOT additionally escaped — pass pre-escaped text.
    static func markdownToHTML(_ escaped: String) -> String {
        var result = escaped

        // Fenced code blocks — must run before inline patterns to avoid mangling backticks
        result = fencedCodeBlockPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1"   // replaced by the transform closure below
        )
        // NSRegularExpression template replacement doesn't support closures;
        // use manual iteration instead.
        result = replaceFencedCodeBlocks(in: result)

        // Inline image: ![alt](url) — before bold/italic so * inside alt isn't mangled
        result = inlineImagePattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "<img src=\"$2\" alt=\"$1\">"
        )

        // Inline code (single backtick)
        result = inlineCodePattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "<code>$1</code>"
        )

        // Bold (**text**)
        result = boldPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "<strong>$1</strong>"
        )

        // Italic (*text*) — run after bold so ** is already consumed
        result = italicPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "<em>$1</em>"
        )

        // Paragraph breaks: two or more newlines → </p><p>
        result = result.replacingOccurrences(of: "\n\n", with: "</p><p>")

        return "<p>\(result)</p>"
    }

    // MARK: - Private helpers

    private static func thinkingHTML(_ entry: ChatEntry) -> String {
        let id = entry.id.uuidString
        let content = htmlEscape(entry.thinkingText)
        return """
        <div class="thinking" data-id="\(id)">
          <button class="thinking-toggle" \
        onclick="merlin.toggleThinking('\(id)')">Thinking ▾</button>
          <div class="thinking-body">\(content)</div>
        </div>
        """
    }

    private static func toolHTML(_ entry: ChatEntry) -> String {
        let id = entry.id.uuidString
        let name = htmlEscape(entry.toolName ?? "tool")
        let errorClass = entry.toolIsError ? " tool-error" : ""
        var inner = ""
        if let args = entry.toolArguments, !args.isEmpty {
            inner += """
            <div class="tool-args"><pre><code>\(htmlEscape(args))</code></pre></div>
            """
        }
        if let result = entry.toolResult {
            inner += """
            <div class="tool-result"><pre><code>\(htmlEscape(result))</code></pre></div>
            """
        }
        return """
        <div class="message tool\(errorClass)" data-id="\(id)">
          <div class="tool-header">
            <span class="tool-name">\(name)</span>
            <button class="tool-toggle" \
        onclick="merlin.toggleTool('\(id)')">▾</button>
          </div>
          <div class="tool-body">\(inner)</div>
        </div>
        """
    }

    private static func replaceFencedCodeBlocks(in text: String) -> String {
        // Pattern: ```lang\ncontent\n```
        // Captures: (1) language tag (may be empty), (2) content
        var result = text
        let pattern = try! NSRegularExpression(
            pattern: #"```(\w*)\n([\s\S]*?)```"#,
            options: []
        )
        // Work backwards so replacement ranges stay valid
        let matches = pattern.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange  = Range(match.range,       in: result),
                  let langRange  = Range(match.range(at: 1), in: result),
                  let bodyRange  = Range(match.range(at: 2), in: result) else { continue }
            let lang = String(result[langRange])
            let body = String(result[bodyRange])
            let langAttr = lang.isEmpty ? "" : " class=\"language-\(lang)\""
            let replacement = "<pre><code\(langAttr)>\(body)</code></pre>"
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    // MARK: - Compiled regex patterns

    private static let fencedCodeBlockPattern = try! NSRegularExpression(
        pattern: #"```(\w*)\n[\s\S]*?```"#, options: [])

    private static let inlineImagePattern = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(((?:https?://|data:)[^)]+)\)"#, options: [])

    private static let inlineCodePattern = try! NSRegularExpression(
        pattern: #"`([^`]+)`"#, options: [])

    private static let boldPattern = try! NSRegularExpression(
        pattern: #"\*\*([^*]+)\*\*"#, options: [])

    private static let italicPattern = try! NSRegularExpression(
        pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, options: [])

    // MARK: - HTML document template

    private static func htmlDocument(body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
            --bg: #1c1c1e;
            --fg: #e5e5ea;
            --fg-secondary: #98989f;
            --bubble-user: #1a3a2a;
            --bubble-assistant: #28283c;
            --bubble-system: transparent;
            --bubble-tool: #1e1e28;
            --bubble-error: #3a1a1a;
            --border: rgba(255,255,255,0.08);
            --code-bg: #0d0d12;
            --thinking-bg: #1a1a28;
            --font: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            --mono: "SF Mono", Menlo, Monaco, "Courier New", monospace;
        }
        @media (prefers-color-scheme: light) {
            :root {
                --bg: #f2f2f7;
                --fg: #1c1c1e;
                --fg-secondary: #6c6c70;
                --bubble-user: #d4edda;
                --bubble-assistant: #e8e8f0;
                --bubble-system: transparent;
                --bubble-tool: #ededf4;
                --bubble-error: #fde8e8;
                --border: rgba(0,0,0,0.08);
                --code-bg: #f0f0f5;
                --thinking-bg: #eeeef8;
            }
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        html, body {
            background: var(--bg);
            color: var(--fg);
            font-family: var(--font);
            font-size: 14px;
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
        }
        #messages {
            display: flex;
            flex-direction: column;
            gap: 12px;
            padding: 16px;
            min-height: 100vh;
        }
        .message {
            border-radius: 14px;
            padding: 12px 14px;
            border: 1px solid var(--border);
            max-width: 100%;
            word-wrap: break-word;
        }
        .message.user      { background: var(--bubble-user); }
        .message.assistant { background: var(--bubble-assistant); }
        .message.system    { background: var(--bubble-system); border-color: transparent;
                             color: var(--fg-secondary); font-size: 12px; text-align: center; }
        .message.error     { background: var(--bubble-error); color: #ff6b6b; }
        .message.tool      { background: var(--bubble-tool); font-size: 12px; }
        .message.tool-error { border-color: rgba(255,100,100,0.4); }
        pre {
            background: var(--code-bg);
            border-radius: 6px;
            padding: 10px;
            overflow-x: auto;
            margin: 8px 0;
            border: 1px solid var(--border);
        }
        code {
            font-family: var(--mono);
            font-size: 12px;
        }
        p code {
            background: var(--code-bg);
            border-radius: 3px;
            padding: 1px 4px;
        }
        p { margin: 4px 0; }
        p:first-child { margin-top: 0; }
        p:last-child  { margin-bottom: 0; }
        img { max-width: 100%; border-radius: 8px; margin: 8px 0; display: block; }
        .thinking {
            background: var(--thinking-bg);
            border-radius: 8px;
            padding: 8px;
            margin-bottom: 8px;
            font-size: 12px;
            color: var(--fg-secondary);
        }
        .thinking-toggle {
            background: none; border: none; cursor: pointer;
            color: var(--fg-secondary); font-size: 12px; padding: 0;
            margin-bottom: 4px; display: block;
        }
        .thinking-body { white-space: pre-wrap; }
        .tool-header { display: flex; justify-content: space-between; align-items: center; }
        .tool-name   { font-family: var(--mono); font-weight: 600; }
        .tool-toggle { background: none; border: none; cursor: pointer;
                       color: var(--fg-secondary); font-size: 11px; }
        .tool-body   { margin-top: 6px; }
        .tool-args, .tool-result { margin-top: 4px; }
        </style>
        </head>
        <body>
        <div id="messages">
        \(body)
        </div>
        <script>
        const merlin = {
            addMessage: function(html) {
                document.getElementById('messages').insertAdjacentHTML('beforeend', html);
                merlin.scrollToBottom();
            },
            updateMessage: function(id, html) {
                const el = document.querySelector('[data-id="' + id + '"]');
                if (el) { el.outerHTML = html; }
            },
            appendChunk: function(id, html) {
                const el = document.querySelector('[data-id="' + id + '"]');
                if (el) { el.outerHTML = html; } else { merlin.addMessage(html); }
                merlin.scrollToBottom();
            },
            scrollToBottom: function() {
                window.scrollTo({ top: document.body.scrollHeight, behavior: 'instant' });
            },
            toggleThinking: function(id) {
                window.webkit.messageHandlers.merlinBridge.postMessage(
                    { type: 'toggleThinking', id: id });
            },
            toggleTool: function(id) {
                window.webkit.messageHandlers.merlinBridge.postMessage(
                    { type: 'toggleTool', id: id });
            },
            setTheme: function(vars) {
                const root = document.documentElement;
                for (const [k, v] of Object.entries(vars)) {
                    root.style.setProperty(k, v);
                }
            }
        };
        </script>
        </body>
        </html>
        """
    }
}
```

---

## New file: `Merlin/Views/Chat/ConversationWebView.swift`

```swift
import SwiftUI
import WebKit

/// A `WKWebView`-backed conversation renderer that replaces the SwiftUI
/// `Text`-per-message list. A single WebView = one contiguous selection
/// surface; native macOS drag selection spans all messages freely.
///
/// Rendering strategy:
/// - **Initial load:** `loadHTMLString` with the full document from
///   `ConversationHTMLRenderer.render(entries)`.
/// - **New messages:** `evaluateJavaScript("merlin.addMessage(html)")` — appends
///   without reloading the page.
/// - **Streaming:** `evaluateJavaScript("merlin.appendChunk(id, html)")` — replaces
///   the last assistant bubble in place as tokens arrive.
/// - **Interactive events** (thinking toggle, tool toggle): JavaScript posts to
///   `merlinBridge`; the `Coordinator: WKScriptMessageHandler` relays to Swift callbacks.
struct ConversationWebView: NSViewRepresentable {
    let entries: [ChatEntry]
    var onToggleThinking: (UUID) -> Void
    var onToggleTool: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToggleThinking: onToggleThinking, onToggleTool: onToggleTool)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "merlinBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")  // transparent — SwiftUI bg shows through
        webView.allowsMagnification = false

        // Disable navigation so links in message text don't navigate away
        webView.navigationDelegate = context.coordinator

        let html = ConversationHTMLRenderer.render(entries)
        let baseURL = FileManager.default.homeDirectoryForCurrentUser
        webView.loadHTMLString(html, baseURL: baseURL)

        context.coordinator.webView = webView
        context.coordinator.renderedCount = entries.count

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        let old = coord.renderedCount
        let new = entries.count

        guard new >= old else {
            // Entries were cleared (new session) — full reload
            let html = ConversationHTMLRenderer.render(entries)
            webView.loadHTMLString(html,
                                   baseURL: FileManager.default.homeDirectoryForCurrentUser)
            coord.renderedCount = new
            coord.lastStreamingID = nil
            return
        }

        if new > old {
            // Append brand-new entries that weren't rendered yet
            let newEntries = Array(entries[old..<new])
            for entry in newEntries {
                let fragment = ConversationHTMLRenderer.messageHTML(for: entry)
                let escaped = jsStringEscape(fragment)
                webView.evaluateJavaScript("merlin.addMessage('\(escaped)')", completionHandler: nil)
            }
            coord.renderedCount = new
        }

        // Streaming: update the last assistant entry if its text changed
        if let last = entries.last, last.role == .assistant {
            let currentID = last.id
            if coord.lastStreamingID == currentID {
                // Same streaming message — update in place
                let chunk = ConversationHTMLRenderer.chunkHTML(for: last)
                let escaped = jsStringEscape(chunk)
                webView.evaluateJavaScript(
                    "merlin.appendChunk('\(currentID.uuidString)', '\(escaped)')",
                    completionHandler: nil
                )
            } else if new == old {
                // Last entry existed before but its text changed (streaming started)
                coord.lastStreamingID = currentID
                let chunk = ConversationHTMLRenderer.chunkHTML(for: last)
                let escaped = jsStringEscape(chunk)
                webView.evaluateJavaScript(
                    "merlin.appendChunk('\(currentID.uuidString)', '\(escaped)')",
                    completionHandler: nil
                )
            }
        } else {
            coord.lastStreamingID = nil
        }
    }

    // MARK: – JS string escaping

    /// Escapes a Swift string for safe embedding inside a JS single-quoted string literal.
    private func jsStringEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'",  with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    // MARK: – Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onToggleThinking: (UUID) -> Void
        var onToggleTool: (UUID) -> Void
        weak var webView: WKWebView?
        var renderedCount: Int = 0
        var lastStreamingID: UUID? = nil

        init(onToggleThinking: @escaping (UUID) -> Void,
             onToggleTool: @escaping (UUID) -> Void) {
            self.onToggleThinking = onToggleThinking
            self.onToggleTool = onToggleTool
        }

        // WKScriptMessageHandler — receives JS merlinBridge.postMessage calls
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "merlinBridge",
                  let body = message.body as? [String: String],
                  let type = body["type"],
                  let idString = body["id"],
                  let id = UUID(uuidString: idString) else { return }

            DispatchQueue.main.async {
                switch type {
                case "toggleThinking": self.onToggleThinking(id)
                case "toggleTool":     self.onToggleTool(id)
                default: break
                }
            }
        }

        // WKNavigationDelegate — block external navigation; allow initial load
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            switch action.navigationType {
            case .other: decisionHandler(.allow)   // loadHTMLString
            default:     decisionHandler(.cancel)   // link clicks, form submits, etc.
            }
        }
    }
}
```

---

## Edit: `Merlin/Views/ChatView.swift`

Replace the `messageList` computed property and its `VStack`+`ForEach` contents with `ConversationWebView`. The `ChatEntryRow`, `RenderedMessage`, and `markdownText` helpers are no longer needed in `ChatView` — they remain in the file for now but are superseded; they can be removed in a follow-up cleanup phase.

### Replace `messageList`

Find:
```swift
    @ViewBuilder
    private var messageList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                if let subagentID = item.subagentID,
                   let subagentVM = model.subagentVMs[subagentID] {
                    SubagentBlockView(vm: subagentVM)
                        .id(item.id)
                } else {
                    ChatEntryRow(
                        item: item,
                        onToggleThinking: item.role == .assistant ? {
                            model.toggleThinkingExpansion(at: index)
                        } : nil,
                        onToggleTool: item.role == .tool ? {
                            model.toggleToolExpansion(at: index)
                        } : nil
                    )
                    .id(item.id)
                }
            }

            Color.clear
                .frame(height: 1)
                .id("bottom")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Single unified selection context for the entire message list so the
        // user can drag-select text across multiple message bubbles.
        .textSelection(.enabled)
    }
```

Replace with:
```swift
    @ViewBuilder
    private var messageList: some View {
        ConversationWebView(
            entries: model.items,
            onToggleThinking: { id in
                if let index = model.items.firstIndex(where: { $0.id == id }) {
                    model.toggleThinkingExpansion(at: index)
                }
            },
            onToggleTool: { id in
                if let index = model.items.firstIndex(where: { $0.id == id }) {
                    model.toggleToolExpansion(at: index)
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

Remove the `proxy.scrollTo("bottom", anchor: .bottom)` calls from `scrollContent` — the
WKWebView's own JS `merlin.scrollToBottom()` handles auto-scroll during streaming. The
`ScrollViewReader` wrapper and `ScrollView` can be removed; `ConversationWebView` scrolls
internally via WebKit's native scroll view.

### Replace `scrollContent`

Find:
```swift
    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        if #available(macOS 15.0, *) {
            ScrollView {
                messageList
            }
            ...
        } else {
            ScrollView {
                messageList
            }
            ...
        }
    }
```

Replace with:
```swift
    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        messageList
    }
```

Also remove `ScrollViewReader { proxy in ... }` from `body` — replace it with a plain
`messageList` call since the proxy is no longer needed.

---

## Verify

```bash
cd ~/Documents/localProject/merlin

# All 166a tests must pass
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    -only-testing "MerlinTests/ConversationHTMLRendererTests" 2>&1 \
    | grep -E 'passed|failed|error:|BUILD'

# Full suite must still pass
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Suite.*passed|Suite.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `ConversationHTMLRendererTests` — all tests passed. Full suite — BUILD SUCCEEDED.

Manual checks after launching the app:
- Messages render correctly for user, assistant, tool, system, error roles
- Code blocks appear in monospace with dark background
- Drag-select works across multiple messages (primary goal)
- Cmd+C copies the selection
- Thinking toggle button fires `onToggleThinking` (check via tool call that has thinking text)
- Streaming appends tokens progressively without page flicker
- Dark/light mode: CSS `prefers-color-scheme` switches automatically

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/Chat/ConversationHTMLRenderer.swift \
        Merlin/Views/Chat/ConversationWebView.swift \
        Merlin/Views/ChatView.swift \
        phases/phase-166b-wkwebview-chat.md
git commit -m "Phase 166b — WKWebView conversation renderer (cross-message selection)"
```
