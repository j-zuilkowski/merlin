# Task diag-09b — Floating & Help Windows Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Task diag-09a complete.

Three files implement the window management subsystem:

---

## Write to: Merlin/Windows/FloatingWindowManager.swift

Pop-out chat windows for individual sessions. A session can be "popped out" into its own
floating `NSWindow` (optionally always-on-top). The manager holds strong `[UUID: NSWindow]`
references to prevent deallocation. Clicking "Close" or the window's close button both
clean up the entry.

Key design decisions:
- `isRuntimeWindowAvailable` guard — returns a stub view in XCTest to avoid AppKit crashes
- `NSWindowDelegate` (via `WindowCloseTracker`) removes closed windows from the map
- `window.isReleasedWhenClosed = false` — prevents double-release under ARC

```swift
import AppKit
import SwiftUI

@MainActor
final class FloatingWindowManager: ObservableObject {
    static let shared = FloatingWindowManager()

    private var windows: [UUID: NSWindow] = [:]
    private var trackers: [UUID: WindowCloseTracker] = [:]

    var openWindowCount: Int {
        windows.count
    }

    func open(session: Session, alwaysOnTop: Bool) {
        executeOnMain {
            self.openOnMain(session: session, alwaysOnTop: alwaysOnTop)
        }
    }

    func close(sessionID: UUID) {
        executeOnMain {
            self.closeOnMain(sessionID: sessionID)
        }
    }

    private func openOnMain(session: Session, alwaysOnTop: Bool) {
        if let window = windows[session.id] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = session.title
        window.isReleasedWhenClosed = false
        if alwaysOnTop {
            window.level = .floating
        }

        let rootView: AnyView
        if isRuntimeWindowAvailable {
            rootView = AnyView(FloatingChatView(session: session, manager: self))
        } else {
            rootView = AnyView(FloatingWindowStubView(title: session.title))
        }

        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        let tracker = WindowCloseTracker(sessionID: session.id, manager: self)
        window.delegate = tracker
        windows[session.id] = window
        trackers[session.id] = tracker
    }

    private func closeOnMain(sessionID: UUID) {
        windows[sessionID]?.close()
        remove(sessionID: sessionID)
    }

    fileprivate func remove(sessionID: UUID) {
        windows.removeValue(forKey: sessionID)
        trackers.removeValue(forKey: sessionID)
    }

    private var isRuntimeWindowAvailable: Bool {
        ProcessInfo.processInfo.processName != "xctest" &&
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private func executeOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}

@MainActor
private final class WindowCloseTracker: NSObject, NSWindowDelegate {
    private let sessionID: UUID
    private weak var manager: FloatingWindowManager?

    init(sessionID: UUID, manager: FloatingWindowManager) {
        self.sessionID = sessionID
        self.manager = manager
    }

    func windowWillClose(_ notification: Notification) {
        manager?.remove(sessionID: sessionID)
    }
}

private struct FloatingWindowStubView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text("Floating window placeholder")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FloatingChatView: View {
    let session: Session
    let manager: FloatingWindowManager

    var body: some View {
        VStack(spacing: 0) {
            ChatView()
            HStack {
                Spacer()
                Button("Close") {
                    manager.close(sessionID: session.id)
                }
                .padding(8)
            }
        }
    }
}
```

**Public API:**
```swift
FloatingWindowManager.shared.open(session:alwaysOnTop:)   // opens or brings to front
FloatingWindowManager.shared.close(sessionID:)             // closes programmatically
FloatingWindowManager.shared.openWindowCount               // current open window count
```

---

## Write to: Merlin/Windows/HelpWindowManager.swift

Retains strong `[NSWindow]` references for programmatically-created help windows.
Without this manager the window is deallocated the moment `open()` returns, causing
a crash on close.

```swift
// HelpWindowManager — holds strong references to open help windows.
//
// NSWindow created programmatically must be retained by someone other than
// the run loop. Without this manager the window is deallocated the moment
// openHelp() returns, causing a crash when the user later closes it.
import AppKit
import SwiftUI

@MainActor
final class HelpWindowManager: NSObject, NSWindowDelegate {
    static let shared = HelpWindowManager()

    private var windows: [NSWindow] = []

    func open(_ document: HelpDocument) {
        // Bring existing window to front rather than opening a duplicate
        if let existing = windows.first(where: { $0.title == document.title }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostView = NSHostingView(
            rootView: NavigationStack {
                HelpWindowView(document: document)
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = document.title
        window.contentView = hostView
        window.delegate = self
        // Prevent the ARC double-release crash: by default NSWindows created
        // programmatically send an extra release on close; under ARC this is a
        // double-free when our windows array also releases the strong reference.
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)   // ← keeps the window alive
    }

    // Remove from the strong-reference array only after the window has closed.
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            self.windows.removeAll { $0 === window }
        }
    }
}
```

**Public API:**
```swift
HelpWindowManager.shared.open(_ document: HelpDocument)  // opens or brings to front
```

---

## Write to: Merlin/Windows/HelpWindowView.swift

In-app documentation viewer. Loads a `.md` file from the bundle and renders it
via an inline `WKWebView` using `MarkdownToHTML.convert()`.

```swift
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
        var loadedHTML: String = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
// Handles: ATX headings, fenced code blocks, tables, unordered/ordered lists,
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
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 14px;
               line-height: 1.65; color: #1d1d1f; max-width: 820px; margin: 0 auto; padding: 32px 40px 60px; }
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
        code { font-family: 'SF Mono', Menlo, Monaco, Consolas, monospace; font-size: 12.5px;
               background: #f3f3f3; border-radius: 3px; padding: 1px 5px; }
        pre { background: #f6f8fa; border: 1px solid #ddd; border-radius: 6px;
              padding: 14px 16px; overflow-x: auto; margin: 1em 0; }
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

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let escaped = codeLines.map(escapeHTML).joined(separator: "\n")
                    let langAttr = codeLang.isEmpty ? "" : " class=\"language-\(codeLang)\""
                    output += "<pre><code\(langAttr)>\(escaped)</code></pre>\n"
                    codeLines = []; codeLang = ""; inCodeBlock = false
                } else {
                    flushList()
                    if inTable { inTable = false; output += "</table>\n" }
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
                i += 1; continue
            }
            if inCodeBlock { codeLines.append(line); i += 1; continue }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushList()
                if inTable { inTable = false; output += "</table>\n" }
                output += "\n"; i += 1; continue
            }

            if line.hasPrefix("|") {
                let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .dropFirst().dropLast()
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ $0.hasPrefix("-") || $0.hasPrefix(":") || $0.isEmpty }) {
                    i += 1; continue
                }
                if !inTable {
                    flushList()
                    output += "<table>\n<tr>"
                    for cell in cells { output += "<th>\(renderInline(cell))</th>" }
                    output += "</tr>\n"; inTable = true
                } else {
                    output += "<tr>"
                    for cell in cells { output += "<td>\(renderInline(cell))</td>" }
                    output += "</tr>\n"
                }
                i += 1; continue
            }
            if inTable { inTable = false; output += "</table>\n" }

            if line.hasPrefix("# ") { flushList()
                let id = anchorID(line.dropFirst(2))
                output += "<h1 id=\"\(id)\">\(renderInline(String(line.dropFirst(2))))</h1>\n"
                i += 1; continue }
            if line.hasPrefix("## ") { flushList()
                let id = anchorID(line.dropFirst(3))
                output += "<h2 id=\"\(id)\">\(renderInline(String(line.dropFirst(3))))</h2>\n"
                i += 1; continue }
            if line.hasPrefix("### ") { flushList()
                let id = anchorID(line.dropFirst(4))
                output += "<h3 id=\"\(id)\">\(renderInline(String(line.dropFirst(4))))</h3>\n"
                i += 1; continue }
            if line.hasPrefix("#### ") { flushList()
                output += "<h4>\(renderInline(String(line.dropFirst(5))))</h4>\n"
                i += 1; continue }

            if line == "---" || line == "***" || line == "___" {
                flushList(); output += "<hr>\n"; i += 1; continue }
            if line.hasPrefix("> ") {
                flushList()
                output += "<blockquote>\(renderInline(String(line.dropFirst(2))))</blockquote>\n"
                i += 1; continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if inList && listOrdered { flushList() }
                inList = true; listOrdered = false
                listItems.append(renderInline(String(line.dropFirst(2))))
                i += 1; continue }

            let orderedPattern = #"^\d+\. (.+)$"#
            if line.range(of: orderedPattern, options: .regularExpression) != nil {
                if inList && !listOrdered { flushList() }
                inList = true; listOrdered = true
                let itemText = String(line[line.index(line.startIndex, offsetBy: line.firstIndex(of: ".")!.utf16Offset(in: line) + 2)...])
                listItems.append(renderInline(itemText))
                i += 1; continue }

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

    private static func renderInline(_ text: String) -> String {
        var s = escapeHTML(text)
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
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
```

Key types:
- `HelpDocument` — enum `.userGuide` / `.developerManual`; `title`, `filename`, `id`
- `HelpWindowView` — SwiftUI view; `@State var html`, loads async via `.task`
- `HelpWebView` — `NSViewRepresentable` WKWebView; idempotent `updateNSView` guard
- `MarkdownToHTML` — stateless converter; handles the subset used in UserGuide/DeveloperManual

## Integration
Triggered from `MerlinCommands`:
```swift
// Help menu
Button("User Guide") { HelpWindowManager.shared.open(.userGuide) }
Button("Developer Manual") { HelpWindowManager.shared.open(.developerManual) }
```
Session pop-out button in ChatView toolbar calls `FloatingWindowManager.shared.open(session:alwaysOnTop:false)`.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'WorkspaceLayout|BUILD SUCCEEDED|BUILD FAILED'
```

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Windows/FloatingWindowManager.swift \
        Merlin/Windows/HelpWindowManager.swift \
        Merlin/Windows/HelpWindowView.swift \
        tasks/task-diag-09b-windows.md
git commit -m "Task diag-09b — FloatingWindowManager + HelpWindowManager + HelpWindowView"
```
