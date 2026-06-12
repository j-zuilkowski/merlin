import Foundation

struct HackerNewsProvider: SearchProvider {
    let id = "hacker_news"
    let httpClient: any HTTPClient
    let clock: any ClockProvider

    init(httpClient: any HTTPClient = URLSessionHTTPClient(), clock: any ClockProvider = SystemClock()) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        guard let url = URL(string: "https://hn.algolia.com/api/v1/search?query=\(DuckDuckGoLiteProvider.percentEncode(request.query))&hitsPerPage=\(settings.maxResultsPerProvider)") else {
            return failure(.parseFailed, "Unable to build Hacker News URL")
        }
        do {
            let response = try await httpClient.get(url, headers: ["User-Agent": settings.userAgent], timeout: TimeInterval(settings.requestTimeoutSeconds), maxBytes: settings.extractionMaxBytes)
            if response.statusCode == 429 { return failure(.rateLimited, "Hacker News Algolia rate limited", sourceURL: url.absoluteString) }
            if response.statusCode >= 400 { return failure(.blocked, "Hacker News Algolia returned HTTP \(response.statusCode)", sourceURL: url.absoluteString) }
            return parse(data: response.data, request: request, sourceURL: url.absoluteString)
        } catch {
            return failure(.timeout, "Hacker News request failed: \(error)", sourceURL: url.absoluteString)
        }
    }

    func parse(data: Data, request: SearchRequest, sourceURL: String? = nil) -> SearchProviderResult {
        struct Envelope: Decodable {
            struct Hit: Decodable {
                var title: String?
                var story_title: String?
                var url: String?
                var story_url: String?
                var objectID: String
                var points: Int?
            }
            var hits: [Hit]
        }
        let now = clock.now()
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return failure(.parseFailed, "Unable to parse Hacker News response", sourceURL: sourceURL)
        }
        let results = envelope.hits.enumerated().compactMap { index, hit -> SearchResult? in
            let url = hit.url ?? hit.story_url ?? "https://news.ycombinator.com/item?id=\(hit.objectID)"
            guard allowed(url, request: request) else { return nil }
            return SearchResult(title: (hit.title ?? hit.story_title ?? "Hacker News item").htmlDecoded(), url: url, canonicalURL: URLCanonicalizer.canonicalize(url), snippet: "Hacker News discussion", providerID: id, rank: index + 1, score: 75 + min(Double(hit.points ?? 0) / 100, 10) - Double(index), retrievedAt: now, diagnostics: [])
        }
        return SearchProviderResult(providerID: id, results: Array(results.prefix(request.count ?? WebSearchSettings.defaults.maxResultsPerProvider)), diagnostic: ProviderDiagnostic(providerID: id, state: results.isEmpty ? .empty : .ok, message: results.isEmpty ? "No Hacker News results" : "Hacker News returned \(results.count) results", retrievedAt: now, sourceURL: sourceURL))
    }

    private func failure(_ state: ProviderDiagnosticState, _ message: String, sourceURL: String? = nil) -> SearchProviderResult {
        SearchProviderResult(providerID: id, results: [], diagnostic: ProviderDiagnostic(providerID: id, state: state, message: message, retrievedAt: clock.now(), sourceURL: sourceURL))
    }
}
