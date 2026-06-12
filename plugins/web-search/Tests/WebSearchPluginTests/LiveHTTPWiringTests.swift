import XCTest
@testable import WebSearchPlugin

final class LiveHTTPWiringTests: XCTestCase {
    func testAllDefaultProvidersUseBoundedHTTPAndNormalizeResponses() async throws {
        let settings = WebSearchSettings.defaults
        let query = "merlin"
        let responses = [
            "https://lite.duckduckgo.com/lite/?q=merlin": HTTPResponse(
                url: URL(string: "https://lite.duckduckgo.com/lite/?q=merlin")!,
                statusCode: 200,
                headers: ["Content-Type": "text/html"],
                data: try fixtureData("duckduckgo", "html")
            ),
            "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=merlin&format=json": HTTPResponse(
                url: URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=merlin&format=json")!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: try fixtureData("wikipedia", "json")
            ),
            "https://api.github.com/search/repositories?q=merlin&per_page=10": HTTPResponse(
                url: URL(string: "https://api.github.com/search/repositories?q=merlin&per_page=10")!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: try fixtureData("github", "json")
            ),
            "https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&q=merlin&site=stackoverflow&pagesize=10": HTTPResponse(
                url: URL(string: "https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&q=merlin&site=stackoverflow&pagesize=10")!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: try fixtureData("stack_exchange", "json")
            ),
            "https://hn.algolia.com/api/v1/search?query=merlin&hitsPerPage=10": HTTPResponse(
                url: URL(string: "https://hn.algolia.com/api/v1/search?query=merlin&hitsPerPage=10")!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: try fixtureData("hacker_news", "json")
            ),
        ]
        let http = MockHTTPClient(responses: responses)
        let providers: [any SearchProvider] = [
            DuckDuckGoLiteProvider(httpClient: http),
            WikipediaProvider(httpClient: http),
            GitHubSearchProvider(httpClient: http),
            StackExchangeProvider(httpClient: http),
            HackerNewsProvider(httpClient: http),
        ]

        let results = await withTaskGroup(of: SearchProviderResult.self, returning: [SearchProviderResult].self) { group in
            for provider in providers {
                group.addTask {
                    await provider.search(SearchRequest(query: query), settings: settings)
                }
            }
            var output: [SearchProviderResult] = []
            for await result in group {
                output.append(result)
            }
            return output
        }

        XCTAssertEqual(results.count, 5)
        XCTAssertTrue(results.allSatisfy { $0.diagnostic.state == .ok })
        XCTAssertTrue(results.allSatisfy { !$0.results.isEmpty })
    }

    func testRateLimitDegradesThroughDiagnostics() async throws {
        let url = URL(string: "https://api.github.com/search/repositories?q=merlin&per_page=10")!
        let provider = GitHubSearchProvider(httpClient: MockHTTPClient(responses: [
            url.absoluteString: HTTPResponse(url: url, statusCode: 403, headers: [:], data: Data())
        ]))

        let result = await provider.search(SearchRequest(query: "merlin"), settings: .defaults)

        XCTAssertEqual(result.diagnostic.state, .rateLimited)
        XCTAssertTrue(result.results.isEmpty)
    }

    func testOptInLiveFreeProvidersReturnResultsOrDiagnostics() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MERLIN_WEB_SEARCH_LIVE_SMOKE"] == "1",
            "Set MERLIN_WEB_SEARCH_LIVE_SMOKE=1 to run live web-search provider smoke tests."
        )
        let providers: [any SearchProvider] = [
            DuckDuckGoLiteProvider(),
            WikipediaProvider(),
            GitHubSearchProvider(),
            StackExchangeProvider(),
            HackerNewsProvider(),
        ]
        var settings = WebSearchSettings.defaults
        settings.requestTimeoutSeconds = 10
        let request = SearchRequest(query: "merlin", count: 3, settings: settings)

        for provider in providers {
            let result = await provider.search(request, settings: settings)
            XCTAssertFalse(result.diagnostic.message.isEmpty, provider.id)
            if result.diagnostic.state == .ok {
                XCTAssertFalse(result.results.isEmpty, provider.id)
            } else {
                XCTAssertTrue(result.results.isEmpty, provider.id)
            }
        }
    }

    func testOptInLiveManagedProvidersReturnResultsOrDiagnosticsWhenKeysExist() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MERLIN_WEB_SEARCH_LIVE_SMOKE"] == "1",
            "Set MERLIN_WEB_SEARCH_LIVE_SMOKE=1 to run live managed provider smoke tests."
        )
        var settings = WebSearchSettings.defaults
        settings.requestTimeoutSeconds = 10
        settings.braveEnabled = ProcessInfo.processInfo.environment["BRAVE_API_KEY"] != nil
        settings.tavilyEnabled = ProcessInfo.processInfo.environment["TAVILY_API_KEY"] != nil
        settings.firecrawlEnabled = ProcessInfo.processInfo.environment["FIRECRAWL_API_KEY"] != nil
        let providers: [any SearchProvider] = [
            BraveSearchProvider(),
            TavilySearchProvider(),
            FirecrawlSearchProvider(),
        ]

        try XCTSkipUnless(
            settings.braveEnabled || settings.tavilyEnabled || settings.firecrawlEnabled,
            "Set at least one of BRAVE_API_KEY, TAVILY_API_KEY, or FIRECRAWL_API_KEY to run managed provider live smoke tests."
        )

        for provider in providers {
            let result = await provider.search(SearchRequest(query: "merlin", count: 3), settings: settings)
            if result.diagnostic.state == .ok {
                XCTAssertFalse(result.results.isEmpty, provider.id)
            } else {
                XCTAssertTrue(result.results.isEmpty, provider.id)
            }
        }
    }
}
