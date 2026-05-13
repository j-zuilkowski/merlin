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
    var onToggleTool: (String) -> Void
    var onScrollLockChange: (Bool) -> Void = { _ in }
    @Binding var shouldResumeScroll: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onToggleThinking: onToggleThinking,
            onToggleTool: onToggleTool,
            onScrollLockChange: onScrollLockChange
        )
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

        // Dispatch a JS resize event when the frame changes so web content reflows correctly.
        let currentFrame = webView.frame
        if currentFrame != coord.lastFrame && !currentFrame.isEmpty {
            coord.lastFrame = currentFrame
            webView.evaluateJavaScript(
                "window.dispatchEvent(new Event('resize'))", completionHandler: nil)
        }

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

        // Streaming: update the most-recent assistant entry when its content changes.
        // Use last(where:) so system notes (compaction, near-ceiling warnings, etc.)
        // at the tail of entries don't prevent tool-call DOM updates for the active
        // assistant bubble — previously those trailing notes caused appendChunk to be
        // skipped entirely, leaving the DOM stale and forcing later iterations to
        // create separate bubbles via addMessage.
        if let last = entries.last(where: { $0.role == .assistant }) {
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
                // Last entry existed before but its text/tool-calls changed (streaming started)
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

        if shouldResumeScroll {
            coord.webView?.evaluateJavaScript("merlin.resumeAutoScroll();", completionHandler: nil)
            DispatchQueue.main.async {
                shouldResumeScroll = false
            }
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
        var onToggleTool: (String) -> Void
        var onScrollLockChange: (Bool) -> Void
        weak var webView: WKWebView?
        var renderedCount: Int = 0
        var lastStreamingID: UUID? = nil
        var lastFrame: CGRect = .zero

        init(onToggleThinking: @escaping (UUID) -> Void,
             onToggleTool: @escaping (String) -> Void,
             onScrollLockChange: @escaping (Bool) -> Void) {
            self.onToggleThinking = onToggleThinking
            self.onToggleTool = onToggleTool
            self.onScrollLockChange = onScrollLockChange
        }

        // WKScriptMessageHandler — receives JS merlinBridge.postMessage calls
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "merlinBridge",
                  let body = message.body as? [String: String] else { return }

            DispatchQueue.main.async {
                self.handleBridgeBody(body)
            }
        }

        /// Processes a decoded bridge message body. Extracted for unit-test access.
        func handleBridgeBody(_ body: [String: String]) {
            guard let type = body["type"] else { return }
            switch type {
            case "toggleThinking":
                guard let id = body["id"].flatMap(UUID.init) else { return }
                onToggleThinking(id)
            case "toggleTool":
                guard let id = body["id"], !id.isEmpty else { return }
                onToggleTool(id)
            case "scrollLock":
                guard let lockedStr = body["locked"] else { return }
                onScrollLockChange(lockedStr == "true")
            default:
                break
            }
        }

        // WKNavigationDelegate — block external navigation; allow initial load
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            switch navigationAction.navigationType {
            case .other: decisionHandler(.allow)   // loadHTMLString
            default:     decisionHandler(.cancel)   // link clicks, form submits, etc.
            }
        }
    }
}
