import XCTest
@testable import WebSearchPlugin

final class ProviderFixtureTests: XCTestCase {
    func testDuckDuckGoFixtureParsesResults() throws {
        let html = try fixtureString("duckduckgo", "html")
        let result = DuckDuckGoLiteProvider().parse(html: html, request: SearchRequest(query: "merlin"))
        XCTAssertEqual(result.diagnostic.state, .ok)
        XCTAssertEqual(result.results.count, 2)
        XCTAssertEqual(result.results.first?.canonicalURL, "https://example.com/alpha")
    }

    func testWikipediaFixtureParsesResults() throws {
        let result = WikipediaProvider().parse(data: try fixtureData("wikipedia", "json"), request: SearchRequest(query: "merlin"))
        XCTAssertEqual(result.diagnostic.state, .ok)
        XCTAssertEqual(result.results.first?.title, "Merlin")
    }

    func testGitHubFixtureParsesResults() throws {
        let result = GitHubSearchProvider().parse(data: try fixtureData("github", "json"), request: SearchRequest(query: "merlin"))
        XCTAssertEqual(result.diagnostic.state, .ok)
        XCTAssertEqual(result.results.first?.url, "https://github.com/owner/project")
    }

    func testStackExchangeFixtureParsesResults() throws {
        let result = StackExchangeProvider().parse(data: try fixtureData("stack_exchange", "json"), request: SearchRequest(query: "swift"))
        XCTAssertEqual(result.diagnostic.state, .ok)
        XCTAssertTrue(result.results.first?.title.contains("Swift") == true)
    }

    func testHackerNewsFixtureParsesResults() throws {
        let result = HackerNewsProvider().parse(data: try fixtureData("hacker_news", "json"), request: SearchRequest(query: "merlin"))
        XCTAssertEqual(result.diagnostic.state, .ok)
        XCTAssertEqual(result.results.first?.providerID, "hacker_news")
    }

    func testBraveFixtureParsesResults() throws {
        let result = BraveSearchProvider().parse(data: try fixtureData("brave", "json"), request: SearchRequest(query: "merlin"))
        XCTAssertEqual(result.diagnostic.state, .ok)
        XCTAssertEqual(result.results.first?.providerID, "brave")
        XCTAssertEqual(result.results.first?.canonicalURL, "https://example.com/brave")
    }

    func testTavilyFixtureParsesResults() throws {
        let result = TavilySearchProvider().parse(data: try fixtureData("tavily", "json"), request: SearchRequest(query: "merlin"))
        XCTAssertEqual(result.diagnostic.state, .ok)
        XCTAssertEqual(result.results.first?.providerID, "tavily")
        XCTAssertEqual(result.results.first?.canonicalURL, "https://example.com/tavily")
    }

    func testFirecrawlFixtureParsesResults() throws {
        let result = FirecrawlSearchProvider().parse(data: try fixtureData("firecrawl", "json"), request: SearchRequest(query: "merlin"))
        XCTAssertEqual(result.diagnostic.state, .ok)
        XCTAssertEqual(result.results.first?.providerID, "firecrawl")
        XCTAssertEqual(result.results.first?.canonicalURL, "https://example.com/firecrawl")
    }

    func testManagedProvidersReturnDisabledWithoutCredentials() async throws {
        var settings = WebSearchSettings.defaults
        settings.braveEnabled = true
        settings.tavilyEnabled = true
        settings.firecrawlEnabled = true

        let brave = await BraveSearchProvider().search(SearchRequest(query: "merlin"), settings: settings)
        let tavily = await TavilySearchProvider().search(SearchRequest(query: "merlin"), settings: settings)
        let firecrawl = await FirecrawlSearchProvider().search(SearchRequest(query: "merlin"), settings: settings)

        XCTAssertEqual(brave.diagnostic.state, .disabled)
        XCTAssertEqual(tavily.diagnostic.state, .disabled)
        XCTAssertEqual(firecrawl.diagnostic.state, .disabled)
    }

    func testMalformedProviderDataReturnsParseFailed() {
        let result = WikipediaProvider().parse(data: Data("not json".utf8), request: SearchRequest(query: "bad"))
        XCTAssertEqual(result.diagnostic.state, .parseFailed)
    }
}
