import Foundation

struct StackExchangeProvider: SearchProvider {
    let id = "stack_exchange"
    let httpClient: any HTTPClient
    let clock: any ClockProvider

    init(httpClient: any HTTPClient = URLSessionHTTPClient(), clock: any ClockProvider = SystemClock()) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        let query = DuckDuckGoLiteProvider.percentEncode(request.query)
        guard let url = URL(string: "https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&q=\(query)&site=stackoverflow&pagesize=\(settings.maxResultsPerProvider)") else {
            return failure(.parseFailed, "Unable to build Stack Exchange URL")
        }
        do {
            let response = try await httpClient.get(url, headers: ["User-Agent": settings.userAgent], timeout: TimeInterval(settings.requestTimeoutSeconds), maxBytes: settings.extractionMaxBytes)
            if response.statusCode == 429 { return failure(.rateLimited, "Stack Exchange API rate limited", sourceURL: url.absoluteString) }
            if response.statusCode >= 400 { return failure(.blocked, "Stack Exchange API returned HTTP \(response.statusCode)", sourceURL: url.absoluteString) }
            return parse(data: response.data, request: request, sourceURL: url.absoluteString)
        } catch {
            return failure(.timeout, "Stack Exchange request failed: \(error)", sourceURL: url.absoluteString)
        }
    }

    func parse(data: Data, request: SearchRequest, sourceURL: String? = nil) -> SearchProviderResult {
        struct Envelope: Decodable {
            struct Item: Decodable {
                var title: String
                var link: String
                var score: Int?
                var is_answered: Bool?
            }
            var items: [Item]
        }
        let now = clock.now()
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return failure(.parseFailed, "Unable to parse Stack Exchange response", sourceURL: sourceURL)
        }
        let results = envelope.items.enumerated().compactMap { index, item -> SearchResult? in
            guard allowed(item.link, request: request) else { return nil }
            let answeredBoost = item.is_answered == true ? 5.0 : 0.0
            return SearchResult(title: item.title.htmlDecoded(), url: item.link, canonicalURL: URLCanonicalizer.canonicalize(item.link), snippet: "", providerID: id, rank: index + 1, score: 80 + answeredBoost + min(Double(item.score ?? 0), 10) - Double(index), retrievedAt: now, diagnostics: [])
        }
        return SearchProviderResult(providerID: id, results: Array(results.prefix(request.count ?? WebSearchSettings.defaults.maxResultsPerProvider)), diagnostic: ProviderDiagnostic(providerID: id, state: results.isEmpty ? .empty : .ok, message: results.isEmpty ? "No Stack Exchange results" : "Stack Exchange returned \(results.count) results", retrievedAt: now, sourceURL: sourceURL))
    }

    private func failure(_ state: ProviderDiagnosticState, _ message: String, sourceURL: String? = nil) -> SearchProviderResult {
        SearchProviderResult(providerID: id, results: [], diagnostic: ProviderDiagnostic(providerID: id, state: state, message: message, retrievedAt: clock.now(), sourceURL: sourceURL))
    }
}
