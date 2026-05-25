# Phase 75 — PreviewPane: WKWebView HTML/Markdown Renderer

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 74 complete: TerminalPane with PTY shell.

Add `PreviewPane` — a SwiftUI view wrapping `WKWebView` via `NSViewRepresentable`.
The pane accepts a `@Binding<URL?>` (for local HTML files) or a `@Binding<String>` for
raw HTML content. It renders HTML and navigates to local file URLs for preview purposes
(e.g. generated docs, README.md rendered as HTML, tool output HTML).

Use two separate views: `PreviewPane` with a URL binding, and keep it simple.

---

## Write to: Merlin/Views/PreviewPane.swift

```swift
import SwiftUI
import WebKit

struct PreviewPane: View {
    @Binding var url: URL?

    var body: some View {
        if let url {
            WebViewRepresentable(url: url)
        } else {
            Text("No preview")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WebViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
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
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/PreviewPane.swift
git commit -m "Phase 75 — PreviewPane: WKWebView NSViewRepresentable for local HTML/file preview"
```
