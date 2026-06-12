import Foundation
@preconcurrency import WebKit

final class WebKitPageExtractor: PageExtractionProvider, @unchecked Sendable {
    let id = "webkit"

    func extract(_ request: PageExtractionRequest, settings: WebSearchSettings) async -> PageExtractionResult {
        await render(request, settings: settings)
    }

    @MainActor
    private func render(_ request: PageExtractionRequest, settings: WebSearchSettings) async -> PageExtractionResult {
        guard let url = URL(string: request.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return blocked(request: request, finalURL: request.url, state: .blocked, message: "Unsupported or invalid URL")
        }
        return await WebKitRenderController(
            request: request,
            url: url,
            settings: settings,
            providerID: id
        ).load()
    }

    private func blocked(request: PageExtractionRequest, finalURL: String, state: ProviderDiagnosticState, message: String) -> PageExtractionResult {
        PageExtractionResult(requestedURL: request.url, finalURL: finalURL, contentType: "text/html", byteCount: 0, title: nil, text: "", strategy: "webkit", truncated: false, diagnostics: [ProviderDiagnostic(providerID: id, state: state, message: message, sourceURL: finalURL)], cached: false)
    }
}

@MainActor
private final class WebKitRenderController: NSObject, WKNavigationDelegate {
    private let request: PageExtractionRequest
    private let url: URL
    private let settings: WebSearchSettings
    private let providerID: String
    private var continuation: CheckedContinuation<PageExtractionResult, Never>?
    private var finished = false
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        return view
    }()

    init(request: PageExtractionRequest, url: URL, settings: WebSearchSettings, providerID: String) {
        self.request = request
        self.url = url
        self.settings = settings
        self.providerID = providerID
    }

    func load() async -> PageExtractionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            var urlRequest = URLRequest(url: url, timeoutInterval: TimeInterval(settings.requestTimeoutSeconds))
            urlRequest.setValue(settings.userAgent, forHTTPHeaderField: "User-Agent")
            webView.load(urlRequest)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(1, settings.requestTimeoutSeconds)) * 1_000_000_000)
                finish(blocked(state: .timeout, message: "WebKit extraction timed out"))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(blocked(state: .blocked, message: "WebKit navigation failed: \(error.localizedDescription)"))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(blocked(state: .blocked, message: "WebKit provisional navigation failed: \(error.localizedDescription)"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.finish(self.blocked(state: .parseFailed, message: "WebKit HTML extraction failed: \(error.localizedDescription)"))
                return
            }
            let html = value as? String ?? ""
            if html.utf8.count > self.settings.extractionMaxBytes {
                self.finish(self.blocked(state: .blocked, message: "Rendered page exceeds configured byte limit"))
                return
            }
            let botPolicy = BotPolicy.evaluate(html: html, settings: self.settings, providerID: self.providerID)
            if botPolicy.blocked {
                self.finish(PageExtractionResult(requestedURL: self.request.url, finalURL: self.webView.url?.absoluteString ?? self.url.absoluteString, contentType: "text/html", byteCount: html.utf8.count, title: nil, text: "", strategy: "webkit", truncated: false, diagnostics: [botPolicy.diagnostic].compactMap { $0 }, cached: false))
                return
            }
            let text = HTMLTextExtractor.extractText(from: html)
            guard text.count > 40 else {
                self.finish(self.blocked(state: .parseFailed, message: "WebKit page could not be converted into useful text"))
                return
            }
            let truncated = text.count > self.settings.extractionMaxBytes
            let output = truncated ? String(text.prefix(self.settings.extractionMaxBytes)) : text
            self.finish(PageExtractionResult(requestedURL: self.request.url, finalURL: self.webView.url?.absoluteString ?? self.url.absoluteString, contentType: "text/html", byteCount: html.utf8.count, title: HTMLTextExtractor.extractTitle(from: html), text: output, strategy: "webkit", truncated: truncated, diagnostics: [botPolicy.diagnostic].compactMap { $0 } + [ProviderDiagnostic(providerID: self.providerID, state: .ok, message: "Rendered page text with bounded WebKit", sourceURL: self.webView.url?.absoluteString ?? self.url.absoluteString)], cached: false))
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let sameDocument = target.host == url.host && target.path == url.path
        decisionHandler(sameDocument ? .allow : .cancel)
    }

    private func blocked(state: ProviderDiagnosticState, message: String) -> PageExtractionResult {
        PageExtractionResult(requestedURL: request.url, finalURL: webView.url?.absoluteString ?? url.absoluteString, contentType: "text/html", byteCount: 0, title: nil, text: "", strategy: "webkit", truncated: false, diagnostics: [ProviderDiagnostic(providerID: providerID, state: state, message: message, sourceURL: webView.url?.absoluteString ?? url.absoluteString)], cached: false)
    }

    private func finish(_ result: PageExtractionResult) {
        guard !finished else { return }
        finished = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}
