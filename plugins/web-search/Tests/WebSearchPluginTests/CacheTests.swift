import XCTest
@testable import WebSearchPlugin

final class CacheTests: XCTestCase {
    func testCacheStoresAndClearsValues() {
        let cache = WebSearchCache<String>()
        cache.store("value", for: "key", ttlSeconds: 60)
        XCTAssertEqual(cache.value(for: "key"), "value")
        cache.clear()
        XCTAssertNil(cache.value(for: "key"))
    }

    func testZeroTTLDoesNotStore() {
        let cache = WebSearchCache<String>()
        cache.store("value", for: "key", ttlSeconds: 0)
        XCTAssertNil(cache.value(for: "key"))
    }

    func testGlobalCacheIsOptInAndSharedAcrossCoordinators() async throws {
        let globalCache = WebSearchCache<SearchResponse>()
        let firstProvider = CountingProvider()
        let secondProvider = CountingProvider()
        let first = SearchCoordinator(providers: [firstProvider], extractor: StubExtractor(), globalCache: globalCache)
        let second = SearchCoordinator(providers: [secondProvider], extractor: StubExtractor(), globalCache: globalCache)
        var settings = WebSearchSettings.defaults
        settings.globalCacheEnabled = true

        let firstResponse = await first.search(SearchRequest(query: "shared", settings: settings))
        let secondResponse = await second.search(SearchRequest(query: "shared", settings: settings))

        XCTAssertFalse(firstResponse.cached)
        XCTAssertTrue(secondResponse.cached)
        XCTAssertEqual(firstProvider.count, 1)
        XCTAssertEqual(secondProvider.count, 0)
    }

    func testWorkspaceCacheRemainsDefaultWhenGlobalCacheDisabled() async throws {
        let globalCache = WebSearchCache<SearchResponse>()
        let firstProvider = CountingProvider()
        let secondProvider = CountingProvider()
        let first = SearchCoordinator(providers: [firstProvider], extractor: StubExtractor(), globalCache: globalCache)
        let second = SearchCoordinator(providers: [secondProvider], extractor: StubExtractor(), globalCache: globalCache)

        _ = await first.search(SearchRequest(query: "workspace-only"))
        _ = await second.search(SearchRequest(query: "workspace-only"))

        XCTAssertEqual(firstProvider.count, 1)
        XCTAssertEqual(secondProvider.count, 1)
    }

    func testCacheKeyIncludesProviderAndSettingsProvenance() {
        var settings = WebSearchSettings.defaults
        let request = SearchRequest(query: "merlin", count: 3, allowedDomains: ["example.com"], settings: settings)
        let first = WebSearchCacheKey.search(request: request, settings: settings, providerIDs: ["wikipedia"])
        settings.maxResultsPerProvider = 20
        let settingsChanged = WebSearchCacheKey.search(request: request, settings: settings, providerIDs: ["wikipedia"])
        let providerChanged = WebSearchCacheKey.search(request: request, settings: settings, providerIDs: ["github"])

        XCTAssertNotEqual(first, settingsChanged)
        XCTAssertNotEqual(settingsChanged, providerChanged)
        XCTAssertTrue(first.contains(WebSearchCacheKey.searchVersion))
    }
}
