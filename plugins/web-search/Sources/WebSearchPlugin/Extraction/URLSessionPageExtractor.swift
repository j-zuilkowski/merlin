import Foundation

struct URLSessionPageExtractor: PageExtractionProvider {
    let id = "extractor"
    let httpClient: any HTTPClient
    let clock: any ClockProvider

    init(httpClient: any HTTPClient = URLSessionHTTPClient(), clock: any ClockProvider = SystemClock()) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func extract(_ request: PageExtractionRequest, settings: WebSearchSettings) async -> PageExtractionResult {
        guard let url = URL(string: request.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return blocked(request: request, finalURL: request.url, contentType: nil, byteCount: 0, state: .blocked, message: "Unsupported or invalid URL")
        }
        do {
            let response = try await httpClient.get(
                url,
                headers: ["User-Agent": settings.userAgent],
                timeout: TimeInterval(settings.requestTimeoutSeconds),
                maxBytes: settings.extractionMaxBytes
            )
            let contentType = response.header("Content-Type")
            let lowerContentType = contentType?.lowercased() ?? ""
            guard response.statusCode < 400 else {
                return blocked(request: request, finalURL: response.url.absoluteString, contentType: contentType, byteCount: response.data.count, state: response.statusCode == 429 ? .rateLimited : .blocked, message: "Page returned HTTP \(response.statusCode)")
            }
            guard lowerContentType.contains("text/html") || lowerContentType.contains("text/plain") || lowerContentType.isEmpty else {
                return blocked(request: request, finalURL: response.url.absoluteString, contentType: contentType, byteCount: response.data.count, state: .unsupportedContent, message: "Unsupported content type \(contentType ?? "unknown")")
            }
            let raw = String(data: response.data, encoding: .utf8) ?? ""
            let botPolicy = BotPolicy.evaluate(html: raw, settings: settings, providerID: id)
            if botPolicy.blocked {
                return PageExtractionResult(requestedURL: request.url, finalURL: response.url.absoluteString, contentType: contentType, byteCount: response.data.count, title: nil, text: "", strategy: "urlsession-html", truncated: false, diagnostics: [botPolicy.diagnostic].compactMap { $0 }, cached: false)
            }
            let text = lowerContentType.contains("text/plain") ? raw : HTMLTextExtractor.extractText(from: raw)
            guard text.count > 40 else {
                return blocked(request: request, finalURL: response.url.absoluteString, contentType: contentType, byteCount: response.data.count, state: .parseFailed, message: "Page could not be converted into useful text")
            }
            return PageExtractionResult(requestedURL: request.url, finalURL: response.url.absoluteString, contentType: contentType, byteCount: response.data.count, title: HTMLTextExtractor.extractTitle(from: raw), text: text, strategy: "urlsession-html", truncated: false, diagnostics: [botPolicy.diagnostic].compactMap { $0 } + [ProviderDiagnostic(providerID: id, state: .ok, message: "Extracted page text", retrievedAt: clock.now(), sourceURL: response.url.absoluteString)], cached: false)
        } catch HTTPClientError.tooLarge(let byteCount) {
            return blocked(request: request, finalURL: request.url, contentType: nil, byteCount: byteCount, state: .blocked, message: "Page exceeds configured byte limit")
        } catch {
            return blocked(request: request, finalURL: request.url, contentType: nil, byteCount: 0, state: .timeout, message: "Page extraction failed: \(error)")
        }
    }

    private func blocked(request: PageExtractionRequest, finalURL: String, contentType: String?, byteCount: Int, state: ProviderDiagnosticState, message: String) -> PageExtractionResult {
        PageExtractionResult(requestedURL: request.url, finalURL: finalURL, contentType: contentType, byteCount: byteCount, title: nil, text: "", strategy: "urlsession-html", truncated: false, diagnostics: [ProviderDiagnostic(providerID: id, state: state, message: message, retrievedAt: clock.now(), sourceURL: finalURL)], cached: false)
    }
}
