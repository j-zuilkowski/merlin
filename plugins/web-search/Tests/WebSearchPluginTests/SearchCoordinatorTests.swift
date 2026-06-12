import XCTest
@testable import WebSearchPlugin

final class SearchCoordinatorTests: XCTestCase {
    func testCoordinatorDedupeRanksAndReportsDiagnostics() async throws {
        let extractor = StubExtractor()
        let coordinator = SearchCoordinator(
            providers: [
                StubProvider(id: "duckduckgo_lite", url: "https://example.com/a?utm_source=x", title: "A", score: 20),
                StubProvider(id: "wikipedia", url: "https://example.com/a", title: "A duplicate", score: 30),
            ],
            extractor: extractor
        )

        let response = await coordinator.search(SearchRequest(query: "a"))

        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results.first?.canonicalURL, "https://example.com/a")
        XCTAssertEqual(response.diagnostics.count, 2)
    }

    func testCoordinatorCacheReturnsCachedResponse() async throws {
        let provider = CountingProvider()
        let coordinator = SearchCoordinator(providers: [provider], extractor: StubExtractor())

        let first = await coordinator.search(SearchRequest(query: "cache"))
        let second = await coordinator.search(SearchRequest(query: "cache"))

        XCTAssertFalse(first.cached)
        XCTAssertTrue(second.cached)
        XCTAssertEqual(provider.count, 1)
    }

    func testSearchAndExtractExtractsTopResults() async throws {
        let coordinator = SearchCoordinator(
            providers: [StubProvider(id: "duckduckgo_lite", url: "https://example.com/a", title: "A")],
            extractor: StubExtractor()
        )

        let response = await coordinator.searchAndExtract(SearchRequest(query: "a"))

        XCTAssertEqual(response.search.results.count, 1)
        XCTAssertEqual(response.extractions.count, 1)
        XCTAssertEqual(response.extractions.first?.text, "Extracted text")
    }

    func testCoordinatorRankingUsesQueryDomainProviderDuplicateAndFreshnessSignals() async throws {
        let now = Date()
        let coordinator = SearchCoordinator(
            providers: [
                StubProvider(
                    id: "duckduckgo_lite",
                    url: "https://random.example.com/page",
                    title: "Unrelated result",
                    snippet: "No strong token match",
                    score: 12,
                    retrievedAt: now.addingTimeInterval(-86400 * 300)
                ),
                StubProvider(
                    id: "github",
                    url: "https://github.com/example/merlin-web-search",
                    title: "Merlin Web Search plugin",
                    snippet: "Native search adapter and extraction code",
                    score: 5,
                    retrievedAt: now
                ),
                StubProvider(
                    id: "wikipedia",
                    url: "https://github.com/example/merlin-web-search?utm_source=x",
                    title: "Merlin web search duplicate",
                    snippet: "Duplicate provider agreement",
                    score: 4,
                    retrievedAt: now
                ),
            ],
            extractor: StubExtractor()
        )

        let response = await coordinator.search(SearchRequest(query: "merlin web search", count: 2))

        XCTAssertEqual(response.results.first?.canonicalURL, "https://github.com/example/merlin-web-search")
        XCTAssertEqual(response.results.first?.rank, 1)
        XCTAssertEqual(response.results.count, 2)
    }
}
