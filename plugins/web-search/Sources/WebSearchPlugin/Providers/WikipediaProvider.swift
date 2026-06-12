import Foundation

struct WikipediaProvider: SearchProvider {
    let id = "wikipedia"
    let httpClient: any HTTPClient
    let clock: any ClockProvider

    init(httpClient: any HTTPClient = URLSessionHTTPClient(), clock: any ClockProvider = SystemClock()) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        let query = DuckDuckGoLiteProvider.percentEncode(request.query)
        guard let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(query)&format=json") else {
            return failure(.parseFailed, "Unable to build Wikipedia URL")
        }
        do {
            let response = try await httpClient.get(url, headers: ["User-Agent": settings.userAgent], timeout: TimeInterval(settings.requestTimeoutSeconds), maxBytes: settings.extractionMaxBytes)
            if response.statusCode == 429 { return failure(.rateLimited, "Wikipedia API rate limited", sourceURL: url.absoluteString) }
            if response.statusCode >= 400 { return failure(.blocked, "Wikipedia API returned HTTP \(response.statusCode)", sourceURL: url.absoluteString) }
            return parse(data: response.data, request: request, sourceURL: url.absoluteString)
        } catch {
            return failure(.timeout, "Wikipedia request failed: \(error)", sourceURL: url.absoluteString)
        }
    }

    func parse(data: Data, request: SearchRequest, sourceURL: String? = nil) -> SearchProviderResult {
        struct Envelope: Decodable {
            struct Query: Decodable {
                struct Item: Decodable {
                    var title: String
                    var snippet: String?
                    var pageid: Int
                }
                var search: [Item]
            }
            var query: Query?
        }
        let now = clock.now()
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return failure(.parseFailed, "Unable to parse Wikipedia response", sourceURL: sourceURL)
        }
        let results = (envelope.query?.search ?? []).enumerated().compactMap { index, item -> SearchResult? in
            let url = "https://en.wikipedia.org/?curid=\(item.pageid)"
            guard allowed(url, request: request) else { return nil }
            return SearchResult(title: item.title, url: url, canonicalURL: URLCanonicalizer.canonicalize(url), snippet: (item.snippet ?? "").strippingHTML().htmlDecoded(), providerID: id, rank: index + 1, score: 90 - Double(index), retrievedAt: now, diagnostics: [])
        }
        return SearchProviderResult(providerID: id, results: Array(results.prefix(request.count ?? WebSearchSettings.defaults.maxResultsPerProvider)), diagnostic: ProviderDiagnostic(providerID: id, state: results.isEmpty ? .empty : .ok, message: results.isEmpty ? "No Wikipedia results" : "Wikipedia returned \(results.count) results", retrievedAt: now, sourceURL: sourceURL))
    }

    private func failure(_ state: ProviderDiagnosticState, _ message: String, sourceURL: String? = nil) -> SearchProviderResult {
        SearchProviderResult(providerID: id, results: [], diagnostic: ProviderDiagnostic(providerID: id, state: state, message: message, retrievedAt: clock.now(), sourceURL: sourceURL))
    }
}
