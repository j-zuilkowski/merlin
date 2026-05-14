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
            return assistantHTML(entry)
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

    /// HTML fragment for an in-progress assistant message. Replaces the full entry
    /// bubble in place via `merlin.appendChunk`. Includes tool call rows so they
    /// remain visible while text streams in. The JS preserves any open tool rows.
    static func chunkHTML(for entry: ChatEntry) -> String {
        assistantHTML(entry)
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

        // Fenced code blocks must be transformed with manual iteration:
        // template replacement cannot generate the final `<pre><code...>` HTML safely.
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

        if result.isEmpty { return "" }

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

    private static func assistantHTML(_ entry: ChatEntry) -> String {
        let id = entry.id.uuidString
        let thinking = entry.thinkingText.isEmpty ? "" : thinkingHTML(entry)
        let toolGroup = entry.toolCalls.isEmpty ? "" : """
        <div class="tool-group">\(entry.toolCalls.map { toolCallHTML($0) }.joined())</div>
        """
        let grounding = entry.groundingReport.map { groundingReportHTML($0) } ?? ""
        let content = markdownToHTML(htmlEscape(entry.text))
        let textDiv = """
        <div class="assistant-text">\(thinking)\(content)</div>
        """
        return """
        <div class="message assistant" data-id="\(id)">\(toolGroup)\(grounding)\(textDiv)</div>
        """
    }

    private static func groundingReportHTML(_ report: GroundingReport) -> String {
        let statusClass: String
        let statusLabel: String
        let detailParts: [String]

        if report.totalChunks == 0 {
            statusClass = "ungrounded"
            statusLabel = "Ungrounded"
            detailParts = ["No retrieved context"]
        } else if report.hasStaleMemory {
            statusClass = "stale-memory"
            statusLabel = "Stale memory"
            detailParts = summaryParts(for: report)
        } else if report.isWellGrounded {
            statusClass = "grounded"
            statusLabel = "Grounded"
            detailParts = summaryParts(for: report)
        } else {
            statusClass = "weak-grounding"
            statusLabel = "Weak grounding"
            detailParts = summaryParts(for: report)
        }

        let details = htmlEscape(detailParts.joined(separator: " · "))
        return """
        <div class="grounding-report \(statusClass)">
          <span class="grounding-status">\(htmlEscape(statusLabel))</span>
          <span class="grounding-meta">\(details)</span>
        </div>
        """
    }

    private static func summaryParts(for report: GroundingReport) -> [String] {
        var parts: [String] = [
            "\(report.totalChunks) chunk\(report.totalChunks == 1 ? "" : "s")",
            "\(report.memoryChunks) memory",
            "\(report.bookChunks) book",
            String(format: "avg %.2f", report.averageScore)
        ]
        if let oldest = report.oldestMemoryAgeDays {
            parts.append("oldest \(oldest)d")
        }
        if report.hasStaleMemory {
            parts.append("stale memory")
        }
        return parts
    }

    private static func toolCallHTML(_ call: ToolCallEntry) -> String {
        let errorClass = call.isError ? " tool-error" : ""
        let statusLabel: String
        if call.result == nil {
            statusLabel = "<span class=\"tool-status\">running…</span>"
        } else if call.isError {
            statusLabel = "<span class=\"tool-status error\">error</span>"
        } else {
            statusLabel = "<span class=\"tool-status\">done</span>"
        }
        var inner = ""
        if !call.arguments.isEmpty {
            inner += """
            <div class="tool-args"><pre><code>\(htmlEscape(call.arguments))</code></pre></div>
            """
        }
        if let result = call.result {
            inner += """
            <div class="tool-result"><pre><code>\(htmlEscape(result))</code></pre></div>
            """
        }
        return """
        <details class="tool-row\(errorClass)" data-tool-id="\(htmlEscape(call.id))">
          <summary class="tool-header">
            <span class="tool-icon">⚙</span>
            <span class="tool-name">\(htmlEscape(call.name))</span>
            \(statusLabel)
            <span class="tool-toggle"></span>
          </summary>
          <div class="tool-body">\(inner)</div>
        </details>
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
            width: 100%;
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
        /* Tool calls are rendered inside the assistant bubble, not as separate items */
        .tool-group { margin-bottom: 8px; display: flex; flex-direction: column; gap: 4px; }
        .tool-group:empty { display: none; }
        .assistant-text:empty { display: none; }
        .tool-row {
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 6px 10px;
            font-size: 12px;
        }
        .tool-row.tool-error { border-color: rgba(255,100,100,0.4); }
        .grounding-report {
            margin-bottom: 8px;
            padding: 6px 8px;
            border-radius: 8px;
            border: 1px solid var(--border);
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            align-items: baseline;
            font-size: 11px;
            line-height: 1.35;
        }
        .grounding-report.grounded { background: rgba(80, 160, 110, 0.08); }
        .grounding-report.ungrounded { background: rgba(140, 140, 160, 0.08); }
        .grounding-report.weak-grounding { background: rgba(200, 160, 70, 0.08); }
        .grounding-report.stale-memory { background: rgba(220, 120, 70, 0.08); }
        .grounding-status {
            font-weight: 700;
            letter-spacing: 0.02em;
            text-transform: uppercase;
        }
        .grounding-meta {
            color: var(--fg-secondary);
        }
        .tool-header {
            list-style: none;
            display: flex; align-items: center; gap: 8px; cursor: pointer; user-select: none;
        }
        .tool-header::-webkit-details-marker { display: none; }
        .tool-icon { color: var(--fg-secondary); font-size: 11px; }
        .tool-name { font-family: var(--mono); font-weight: 600; flex: 1; }
        .tool-status { font-size: 11px; color: var(--fg-secondary); }
        .tool-status.error { color: #ff8c69; }
        .tool-toggle { color: var(--fg-secondary); font-size: 11px; }
        .tool-toggle::before { content: '▸'; }
        details[open] .tool-toggle::before { content: '▾'; }
        .tool-body { margin-top: 6px; }
        .tool-args, .tool-result { margin-top: 4px; }
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
        </style>
        </head>
        <body>
        <div id="messages">
        \(body)
        </div>
        <script>
        // Scroll-lock: true when user has manually scrolled up >50px from bottom.
        // Auto-scroll is suppressed while locked; addMessage (new turn) always resets it.
        let _userScrolled = false;
        window.addEventListener('scroll', function() {
            const root = document.documentElement;
            const distFromBottom = root.scrollHeight - root.scrollTop - root.clientHeight;
            const nowLocked = distFromBottom > 50;
            if (nowLocked !== _userScrolled) {
                _userScrolled = nowLocked;
                window.webkit.messageHandlers.merlinBridge.postMessage(
                    { type: 'scrollLock', locked: nowLocked ? 'true' : 'false' }
                );
            }
        }, { passive: true });

        const merlin = {
            addMessage: function(html) {
                _userScrolled = false;   // new turn always snaps to bottom
                document.getElementById('messages').insertAdjacentHTML('beforeend', html);
                merlin.scrollToBottom();
            },
            updateMessage: function(id, html) {
                const el = document.querySelector('[data-id="' + id + '"]');
                if (el) { el.outerHTML = html; }
            },
            appendChunk: function(id, html) {
                const el = document.querySelector('[data-id="' + id + '"]');
                if (!el) return;
                // Preserve which tool rows are currently expanded before replacing HTML.
                const openTools = {};
                el.querySelectorAll('[data-tool-id]').forEach(function(row) {
                    openTools[row.getAttribute('data-tool-id')] = row.open;
                });
                el.outerHTML = html;
                // Re-open any tool rows that were open before the replace.
                Object.keys(openTools).forEach(function(toolId) {
                    if (!openTools[toolId]) return;
                    const row = document.querySelector('[data-tool-id="' + toolId + '"]');
                    if (row) row.open = true;
                });
                if (!_userScrolled) { merlin.scrollToBottom(); }
            },
            scrollToBottom: function() {
                // Use documentElement — WKWebView on macOS scrolls the <html> root, not body.
                const root = document.documentElement;
                root.scrollTop = root.scrollHeight;
            },
            resumeAutoScroll: function() {
                _userScrolled = false;
                merlin.scrollToBottom();
            },
            toggleThinking: function(id) {
                window.webkit.messageHandlers.merlinBridge.postMessage(
                    { type: 'toggleThinking', id: id });
            },
            toggleTool: function(id) {
                const row = document.querySelector('[data-tool-id="' + id + '"]');
                if (row) row.open = !row.open;
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
