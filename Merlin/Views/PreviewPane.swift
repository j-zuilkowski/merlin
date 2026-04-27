import SwiftUI
import WebKit

struct PreviewPane: View {
    @Binding var url: URL?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let url {
                PreviewWebView(url: url)
            } else {
                placeholder
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Preview")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            if url != nil {
                Button {
                    url = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Close preview")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text("No preview selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

private struct PreviewWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(url: url, into: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.load(url: url, into: nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loadedURL: URL?

        func load(url: URL, into webView: WKWebView) {
            guard loadedURL != url else { return }
            loadedURL = url
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}
