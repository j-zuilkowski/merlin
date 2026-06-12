import Foundation

struct DuckDuckGoLiteProvider: SearchProvider {
    let id = "duckduckgo_lite"
    let httpClient: any HTTPClient
    let clock: any ClockProvider

    init(httpClient: any HTTPClient = URLSessionHTTPClient(), clock: any ClockProvider = SystemClock()) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        guard let url = URL(string: "https://lite.duckduckgo.com/lite/?q=\(Self.percentEncode(request.query))") else {
            return failure(.parseFailed, "Unable to build DuckDuckGo Lite URL")
        }
        do {
            let response = try await httpClient.get(
                url,
                headers: ["User-Agent": settings.userAgent],
                timeout: TimeInterval(settings.requestTimeoutSeconds),
                maxBytes: settings.extractionMaxBytes
            )
            if response.statusCode == 429 { return failure(.rateLimited, "DuckDuckGo Lite rate limited", sourceURL: url.absoluteString) }
            if response.statusCode >= 400 { return failure(.blocked, "DuckDuckGo Lite returned HTTP \(response.statusCode)", sourceURL: url.absoluteString) }
            let html = String(data: response.data, encoding: .utf8) ?? ""
            return parse(html: html, request: request, sourceURL: url.absoluteString)
        } catch {
            return failure(.timeout, "DuckDuckGo Lite request failed: \(error)", sourceURL: url.absoluteString)
        }
    }

    func parse(html: String, request: SearchRequest, sourceURL: String? = nil) -> SearchProviderResult {
        let now = clock.now()
        let pattern = #"<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>"#
        let matches = html.regexMatches(pattern: pattern)
        var rank = 1
        let results: [SearchResult] = matches.compactMap { match in
            guard match.count >= 3 else { return nil }
            let rawURL = match[1].htmlDecoded()
            let title = match[2].strippingHTML().htmlDecoded().trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.isEmpty == false,
                  rawURL.hasPrefix("http"),
                  allowed(rawURL, request: request) else {
                return nil
            }
            defer { rank += 1 }
            return SearchResult(
                title: title,
                url: rawURL,
                canonicalURL: URLCanonicalizer.canonicalize(rawURL),
                snippet: "",
                providerID: id,
                rank: rank,
                score: 100 - Double(rank),
                retrievedAt: now,
                diagnostics: []
            )
        }
        let state: ProviderDiagnosticState = results.isEmpty ? .empty : .ok
        return SearchProviderResult(
            providerID: id,
            results: Array(results.prefix(request.count ?? WebSearchSettings.defaults.maxResultsPerProvider)),
            diagnostic: ProviderDiagnostic(providerID: id, state: state, message: results.isEmpty ? "No DuckDuckGo Lite results" : "DuckDuckGo Lite returned \(results.count) results", retrievedAt: now, sourceURL: sourceURL)
        )
    }

    private func failure(_ state: ProviderDiagnosticState, _ message: String, sourceURL: String? = nil) -> SearchProviderResult {
        SearchProviderResult(providerID: id, results: [], diagnostic: ProviderDiagnostic(providerID: id, state: state, message: message, retrievedAt: clock.now(), sourceURL: sourceURL))
    }
}

extension DuckDuckGoLiteProvider {
    static func percentEncode(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    }
}

func allowed(_ rawURL: String, request: SearchRequest) -> Bool {
    guard let host = URL(string: rawURL)?.host?.lowercased() else { return false }
    if request.blockedDomains.contains(where: { host.contains($0.lowercased()) }) {
        return false
    }
    if request.allowedDomains.isEmpty == false,
       request.allowedDomains.contains(where: { host.contains($0.lowercased()) }) == false {
        return false
    }
    return true
}
