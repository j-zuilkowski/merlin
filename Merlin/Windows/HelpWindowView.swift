// HelpWindowView — in-app viewer for bundled Markdown documentation.
//
// Uses WKWebView with a hand-written markdown-to-HTML converter so the
// documents render with full heading/table/code-block formatting.
// TOC anchor links scroll within the page; no external URL is opened.
//
// Opened via MerlinCommands Help menu (⌘? for User Guide).
import SwiftUI
@preconcurrency import WebKit

enum HelpDocument: String, Identifiable {
    case userGuide = "UserGuide"
    case developerManual = "DeveloperManual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userGuide: return "User Guide"
        case .developerManual: return "Developer Manual"
        }
    }

    var filename: String { rawValue }
}

// MARK: - HelpWindowView

struct HelpWindowView: View {
    let document: HelpDocument

    @State private var html: String = ""
    @State private var isLoaded = false

    var body: some View {
        Group {
            if isLoaded {
                HelpWebView(html: html)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(document.title)
        .frame(minWidth: 720, minHeight: 560)
        .task { await loadDocument() }
    }

    private func loadDocument() async {
        guard let url = Bundle.main.url(forResource: document.filename, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            html = "<p>Documentation file not found: \(document.filename).md</p>"
            isLoaded = true
            return
        }
        html = MarkdownToHTML.convert(raw, title: document.title)
        isLoaded = true
    }
}

// MARK: - WKWebView wrapper

struct HelpWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    // Guard against repeated loads: WKWebView crashes when loadHTMLString is
    // called concurrently (e.g. SwiftUI redraw racing with a user-triggered reload).
    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        // Tracks the content currently loaded so updateNSView is idempotent.
        var loadedHTML: String = ""

        // When the user triggers Reload (⌘R or context menu), re-inject the
        // HTML string so the page doesn't go blank (WKWebView reloads about:blank
        // for loadHTMLString loads, which discards our content).
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // If the webView navigated away from our content (e.g. reload → about:blank),
            // reload it from the stored HTML.
            webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                guard let self else { return }
                let title = result as? String ?? ""
                if title.isEmpty && !self.loadedHTML.isEmpty {
                    webView.loadHTMLString(self.loadedHTML, baseURL: nil)
                }
            }
        }
    }
}

// MARK: - Markdown → HTML converter
// Handles the specific subset used in UserGuide.md and DeveloperManual.md:
// ATX headings, fenced code blocks, tables, unordered/ordered lists,
// blockquotes, inline code, bold, italic, and links.

enum MarkdownToHTML {
    static func convert(_ markdown: String, title: String) -> String {
        let body = renderBody(markdown)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(title)</title>
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            font-size: 14px;
            line-height: 1.65;
            color: #1d1d1f;
            max-width: 820px;
            margin: 0 auto;
            padding: 32px 40px 60px;
        }
        @media (prefers-color-scheme: dark) {
            body { background: #1e1e1e; color: #d4d4d4; }
            code { background: #2d2d2d; color: #ce9178; }
            pre { background: #1a1a1a; border-color: #333; }
            table th { background: #2a2a2a; }
            table td, table th { border-color: #444; }
            a { color: #569cd6; }
            hr { border-color: #444; }
        }
        h1 { font-size: 2em; font-weight: 700; border-bottom: 2px solid #eee; padding-bottom: 8px; margin-top: 0; }
        h2 { font-size: 1.4em; font-weight: 600; border-bottom: 1px solid #eee; padding-bottom: 4px; margin-top: 2em; }
        h3 { font-size: 1.15em; font-weight: 600; margin-top: 1.5em; }
        h4 { font-size: 1em; font-weight: 600; }
        code {
            font-family: 'SF Mono', Menlo, Monaco, Consolas, monospace;
            font-size: 12.5px;
            background: #f3f3f3;
            border-radius: 3px;
            padding: 1px 5px;
        }
        pre {
            background: #f6f8fa;
            border: 1px solid #ddd;
            border-radius: 6px;
            padding: 14px 16px;
            overflow-x: auto;
            margin: 1em 0;
        }
        pre code { background: none; padding: 0; font-size: 12.5px; }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        table th { background: #f0f0f0; font-weight: 600; text-align: left; padding: 8px 12px; border: 1px solid #ddd; }
        table td { padding: 7px 12px; border: 1px solid #ddd; vertical-align: top; }
        table tr:nth-child(even) td { background: #fafafa; }
        a { color: #0070f3; text-decoration: none; }
        a:hover { text-decoration: underline; }
        blockquote { border-left: 3px solid #ccc; margin: 0; padding: 0 0 0 16px; color: #555; }
        hr { border: none; border-top: 1px solid #ddd; margin: 2em 0; }
        ul, ol { padding-left: 1.5em; }
        li { margin: 0.25em 0; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // swiftlint:disable:next function_body_length
    private static func renderBody(_ markdown: String) -> String {
        var output = ""
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var inCodeBlock = false
        var codeLang = ""
        var codeLines: [String] = []
        var inTable = false
        var inList = false
        var listOrdered = false
        var listItems: [String] = []

        func flushList() {
            guard inList, !listItems.isEmpty else { return }
            let tag = listOrdered ? "ol" : "ul"
            output += "<\(tag)>\n"
            for item in listItems { output += "<li>\(item)</li>\n" }
            output += "</\(tag)>\n"
            listItems = []
        }

        func flushTable() {
            // already flushed inline
        }

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                if inCodeBlock {
                    let escaped = codeLines.map(escapeHTML).joined(separator: "\n")
                    let langAttr = codeLang.isEmpty ? "" : " class=\"language-\(codeLang)\""
                    output += "<pre><code\(langAttr)>\(escaped)</code></pre>\n"
                    codeLines = []
                    codeLang = ""
                    inCodeBlock = false
                } else {
                    flushList()
                    if inTable { inTable = false; output += "</table>\n" }
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
                i += 1
                continue
            }
            if inCodeBlock {
                codeLines.append(line)
                i += 1
                continue
            }

            // Blank line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushList()
                if inTable { inTable = false; output += "</table>\n" }
                output += "\n"
                i += 1
                continue
            }

            // Table
            if line.hasPrefix("|") {
                let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .dropFirst().dropLast()
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                // Separator row
                if cells.allSatisfy({ $0.hasPrefix("-") || $0.hasPrefix(":") || $0.isEmpty }) {
                    i += 1
                    continue
                }
                if !inTable {
                    flushList()
                    output += "<table>\n<tr>"
                    for cell in cells { output += "<th>\(renderInline(cell))</th>" }
                    output += "</tr>\n"
                    inTable = true
                } else {
                    output += "<tr>"
                    for cell in cells { output += "<td>\(renderInline(cell))</td>" }
                    output += "</tr>\n"
                }
                i += 1
                continue
            }
            if inTable {
                inTable = false
                output += "</table>\n"
            }

            // Headings
            if line.hasPrefix("# ") {
                flushList()
                let id = anchorID(line.dropFirst(2))
                output += "<h1 id=\"\(id)\">\(renderInline(String(line.dropFirst(2))))</h1>\n"
                i += 1; continue
            }
            if line.hasPrefix("## ") {
                flushList()
                let id = anchorID(line.dropFirst(3))
                output += "<h2 id=\"\(id)\">\(renderInline(String(line.dropFirst(3))))</h2>\n"
                i += 1; continue
            }
            if line.hasPrefix("### ") {
                flushList()
                let id = anchorID(line.dropFirst(4))
                output += "<h3 id=\"\(id)\">\(renderInline(String(line.dropFirst(4))))</h3>\n"
                i += 1; continue
            }
            if line.hasPrefix("#### ") {
                flushList()
                output += "<h4>\(renderInline(String(line.dropFirst(5))))</h4>\n"
                i += 1; continue
            }

            // HR
            if line == "---" || line == "***" || line == "___" {
                flushList()
                output += "<hr>\n"
                i += 1; continue
            }

            // Blockquote
            if line.hasPrefix("> ") {
                flushList()
                output += "<blockquote>\(renderInline(String(line.dropFirst(2))))</blockquote>\n"
                i += 1; continue
            }

            // Unordered list
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if inList && listOrdered { flushList() }
                inList = true; listOrdered = false
                listItems.append(renderInline(String(line.dropFirst(2))))
                i += 1; continue
            }

            // Ordered list
            let orderedPattern = #"^\d+\. (.+)$"#
            if line.range(of: orderedPattern, options: .regularExpression) != nil {
                if inList && !listOrdered { flushList() }
                inList = true; listOrdered = true
                let itemText = String(line[line.index(line.startIndex, offsetBy: line.firstIndex(of: ".")!.utf16Offset(in: line) + 2)...])
                listItems.append(renderInline(itemText))
                i += 1; continue
            }

            // Paragraph
            flushList()
            output += "<p>\(renderInline(line))</p>\n"
            i += 1
        }

        flushList()
        if inTable { output += "</table>\n" }
        if inCodeBlock {
            let escaped = codeLines.map(escapeHTML).joined(separator: "\n")
            output += "<pre><code>\(escaped)</code></pre>\n"
        }
        return output
    }

    // Inline markdown: bold, italic, inline code, links
    private static func renderInline(_ text: String) -> String {
        var s = escapeHTML(text)
        // Inline code (must come before bold/italic to avoid mangling backtick content)
        s = s.replacingOccurrences(of: "`([^`]+)`",
                                   with: "<code>$1</code>",
                                   options: .regularExpression)
        // Bold **text**
        s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",
                                   with: "<strong>$1</strong>",
                                   options: .regularExpression)
        // Italic *text*
        s = s.replacingOccurrences(of: "\\*(.+?)\\*",
                                   with: "<em>$1</em>",
                                   options: .regularExpression)
        // Links [text](url)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
                                   with: "<a href=\"$2\">$1</a>",
                                   options: .regularExpression)
        return s
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func anchorID(_ s: some StringProtocol) -> String {
        s.lowercased()
         .replacingOccurrences(of: " ", with: "-")
         .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
    }
}
