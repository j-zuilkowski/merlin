import Foundation

struct FirecrawlSearchProvider: SearchProvider {
    let id = "firecrawl"
    let httpClient: any HTTPClient
    let clock: any ClockProvider

    init(httpClient: any HTTPClient = URLSessionHTTPClient(), clock: any ClockProvider = SystemClock()) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        guard let apiKey = ManagedProviderCredentials.apiKey(settingsValue: settings.firecrawlAPIKey, environmentKey: "FIRECRAWL_API_KEY") else {
            return failure(.disabled, "Firecrawl API key is not configured")
        }
        guard let url = URL(string: "https://api.firecrawl.dev/v1/search") else {
            return failure(.parseFailed, "Unable to build Firecrawl URL")
        }
        do {
            let body = try JSON.objectData([
                "query": request.query,
                "limit": settings.maxResultsPerProvider,
            ])
            let response = try await httpClient.post(url, headers: ["Content-Type": "application/json", "Authorization": "Bearer \(apiKey)", "User-Agent": settings.userAgent], body: body, timeout: TimeInterval(settings.requestTimeoutSeconds), maxBytes: settings.extractionMaxBytes)
            if response.statusCode == 401 || response.statusCode == 403 { return failure(.disabled, "Firecrawl credential rejected", sourceURL: url.absoluteString) }
            if response.statusCode == 429 { return failure(.rateLimited, "Firecrawl API rate limited", sourceURL: url.absoluteString) }
            if response.statusCode >= 400 { return failure(.blocked, "Firecrawl API returned HTTP \(response.statusCode)", sourceURL: url.absoluteString) }
            return parse(data: response.data, request: request, sourceURL: url.absoluteString)
        } catch {
            return failure(.timeout, "Firecrawl request failed: \(error)", sourceURL: url.absoluteString)
        }
    }

    func parse(data: Data, request: SearchRequest, sourceURL: String? = nil) -> SearchProviderResult {
        struct Envelope: Decodable {
            struct Result: Decodable {
                var title: String?
                var url: String
                var description: String?
            }
            var data: [Result]?
            var results: [Result]?
        }
        let now = clock.now()
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return failure(.parseFailed, "Unable to parse Firecrawl response", sourceURL: sourceURL)
        }
        let items = envelope.data ?? envelope.results ?? []
        let results = items.enumerated().compactMap { index, item -> SearchResult? in
            guard allowed(item.url, request: request) else { return nil }
            return SearchResult(title: item.title ?? item.url, url: item.url, canonicalURL: URLCanonicalizer.canonicalize(item.url), snippet: item.description ?? "", providerID: id, rank: index + 1, score: 84 - Double(index), retrievedAt: now, diagnostics: [])
        }
        return SearchProviderResult(providerID: id, results: Array(results.prefix(request.count ?? WebSearchSettings.defaults.maxResultsPerProvider)), diagnostic: ProviderDiagnostic(providerID: id, state: results.isEmpty ? .empty : .ok, message: results.isEmpty ? "No Firecrawl results" : "Firecrawl returned \(results.count) results", retrievedAt: now, sourceURL: sourceURL))
    }

    private func failure(_ state: ProviderDiagnosticState, _ message: String, sourceURL: String? = nil) -> SearchProviderResult {
        SearchProviderResult(providerID: id, results: [], diagnostic: ProviderDiagnostic(providerID: id, state: state, message: message, retrievedAt: clock.now(), sourceURL: sourceURL))
    }
}
