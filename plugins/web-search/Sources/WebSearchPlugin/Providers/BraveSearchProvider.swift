import Foundation

struct BraveSearchProvider: SearchProvider {
    let id = "brave"
    let httpClient: any HTTPClient
    let clock: any ClockProvider

    init(httpClient: any HTTPClient = URLSessionHTTPClient(), clock: any ClockProvider = SystemClock()) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        guard let apiKey = ManagedProviderCredentials.apiKey(settingsValue: settings.braveAPIKey, environmentKey: "BRAVE_API_KEY") else {
            return failure(.disabled, "Brave API key is not configured")
        }
        guard let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(DuckDuckGoLiteProvider.percentEncode(request.query))&count=\(settings.maxResultsPerProvider)") else {
            return failure(.parseFailed, "Unable to build Brave URL")
        }
        do {
            let response = try await httpClient.get(url, headers: ["Accept": "application/json", "X-Subscription-Token": apiKey, "User-Agent": settings.userAgent], timeout: TimeInterval(settings.requestTimeoutSeconds), maxBytes: settings.extractionMaxBytes)
            if response.statusCode == 401 || response.statusCode == 403 { return failure(.disabled, "Brave credential rejected", sourceURL: url.absoluteString) }
            if response.statusCode == 429 { return failure(.rateLimited, "Brave API rate limited", sourceURL: url.absoluteString) }
            if response.statusCode >= 400 { return failure(.blocked, "Brave API returned HTTP \(response.statusCode)", sourceURL: url.absoluteString) }
            return parse(data: response.data, request: request, sourceURL: url.absoluteString)
        } catch {
            return failure(.timeout, "Brave request failed: \(error)", sourceURL: url.absoluteString)
        }
    }

    func parse(data: Data, request: SearchRequest, sourceURL: String? = nil) -> SearchProviderResult {
        struct Envelope: Decodable {
            struct Web: Decodable {
                struct Result: Decodable {
                    var title: String
                    var url: String
                    var description: String?
                    var age: String?
                }
                var results: [Result]
            }
            var web: Web?
        }
        let now = clock.now()
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return failure(.parseFailed, "Unable to parse Brave response", sourceURL: sourceURL)
        }
        let results = (envelope.web?.results ?? []).enumerated().compactMap { index, item -> SearchResult? in
            guard allowed(item.url, request: request) else { return nil }
            return SearchResult(title: item.title, url: item.url, canonicalURL: URLCanonicalizer.canonicalize(item.url), snippet: item.description ?? "", providerID: id, rank: index + 1, score: 88 - Double(index), retrievedAt: now, diagnostics: [])
        }
        return SearchProviderResult(providerID: id, results: Array(results.prefix(request.count ?? WebSearchSettings.defaults.maxResultsPerProvider)), diagnostic: ProviderDiagnostic(providerID: id, state: results.isEmpty ? .empty : .ok, message: results.isEmpty ? "No Brave results" : "Brave returned \(results.count) results", retrievedAt: now, sourceURL: sourceURL))
    }

    private func failure(_ state: ProviderDiagnosticState, _ message: String, sourceURL: String? = nil) -> SearchProviderResult {
        SearchProviderResult(providerID: id, results: [], diagnostic: ProviderDiagnostic(providerID: id, state: state, message: message, retrievedAt: clock.now(), sourceURL: sourceURL))
    }
}
