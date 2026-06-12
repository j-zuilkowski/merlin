import Foundation

struct GitHubSearchProvider: SearchProvider {
    let id = "github"
    let httpClient: any HTTPClient
    let clock: any ClockProvider

    init(httpClient: any HTTPClient = URLSessionHTTPClient(), clock: any ClockProvider = SystemClock()) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        guard let url = URL(string: "https://api.github.com/search/repositories?q=\(DuckDuckGoLiteProvider.percentEncode(request.query))&per_page=\(settings.maxResultsPerProvider)") else {
            return failure(.parseFailed, "Unable to build GitHub URL")
        }
        do {
            let response = try await httpClient.get(url, headers: ["User-Agent": settings.userAgent, "Accept": "application/vnd.github+json"], timeout: TimeInterval(settings.requestTimeoutSeconds), maxBytes: settings.extractionMaxBytes)
            if response.statusCode == 403 || response.statusCode == 429 { return failure(.rateLimited, "GitHub API rate limited or forbidden", sourceURL: url.absoluteString) }
            if response.statusCode >= 400 { return failure(.blocked, "GitHub API returned HTTP \(response.statusCode)", sourceURL: url.absoluteString) }
            return parse(data: response.data, request: request, sourceURL: url.absoluteString)
        } catch {
            return failure(.timeout, "GitHub request failed: \(error)", sourceURL: url.absoluteString)
        }
    }

    func parse(data: Data, request: SearchRequest, sourceURL: String? = nil) -> SearchProviderResult {
        struct Envelope: Decodable {
            struct Item: Decodable {
                var full_name: String
                var html_url: String
                var description: String?
                var stargazers_count: Int?
            }
            var items: [Item]
        }
        let now = clock.now()
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return failure(.parseFailed, "Unable to parse GitHub response", sourceURL: sourceURL)
        }
        let results = envelope.items.enumerated().compactMap { index, item -> SearchResult? in
            guard allowed(item.html_url, request: request) else { return nil }
            return SearchResult(title: item.full_name, url: item.html_url, canonicalURL: URLCanonicalizer.canonicalize(item.html_url), snippet: item.description ?? "", providerID: id, rank: index + 1, score: 85 + min(Double(item.stargazers_count ?? 0) / 10_000, 10) - Double(index), retrievedAt: now, diagnostics: [])
        }
        return SearchProviderResult(providerID: id, results: Array(results.prefix(request.count ?? WebSearchSettings.defaults.maxResultsPerProvider)), diagnostic: ProviderDiagnostic(providerID: id, state: results.isEmpty ? .empty : .ok, message: results.isEmpty ? "No GitHub results" : "GitHub returned \(results.count) results", retrievedAt: now, sourceURL: sourceURL))
    }

    private func failure(_ state: ProviderDiagnosticState, _ message: String, sourceURL: String? = nil) -> SearchProviderResult {
        SearchProviderResult(providerID: id, results: [], diagnostic: ProviderDiagnostic(providerID: id, state: state, message: message, retrievedAt: clock.now(), sourceURL: sourceURL))
    }
}
