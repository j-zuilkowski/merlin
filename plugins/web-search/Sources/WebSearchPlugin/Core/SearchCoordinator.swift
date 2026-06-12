import Foundation

final class SearchCoordinator: @unchecked Sendable {
    private let providers: [any SearchProvider]
    private let extractor: any PageExtractionProvider
    private let cache: WebSearchCache<SearchResponse>
    private let globalCache: WebSearchCache<SearchResponse>
    private let clock: any ClockProvider
    private let ranker = ResultRanker()

    init(
        providers: [any SearchProvider],
        extractor: any PageExtractionProvider,
        cache: WebSearchCache<SearchResponse> = WebSearchCache<SearchResponse>(),
        globalCache: WebSearchCache<SearchResponse> = WebSearchGlobalCaches.search,
        clock: any ClockProvider = SystemClock()
    ) {
        self.providers = providers
        self.extractor = extractor
        self.cache = cache
        self.globalCache = globalCache
        self.clock = clock
    }

    func search(_ request: SearchRequest) async -> SearchResponse {
        let settings = request.settings ?? .defaults
        let enabledProviders = providers.filter { isEnabled($0.id, settings: settings) }
        let cacheKey = WebSearchCacheKey.search(request: request, settings: settings, providerIDs: enabledProviders.map(\.id))
        if var cached = cache.value(for: cacheKey) {
            cached.cached = true
            return cached
        }
        if settings.globalCacheEnabled, var cached = globalCache.value(for: cacheKey) {
            cached.cached = true
            cache.store(cached, for: cacheKey, ttlSeconds: settings.cacheTTLSeconds)
            return cached
        }

        var diagnostics = disabledDiagnostics(settings: settings)
        var providerResults: [SearchProviderResult] = []

        await withTaskGroup(of: SearchProviderResult.self) { group in
            for provider in enabledProviders {
                group.addTask {
                    await provider.search(request, settings: settings)
                }
            }
            for await result in group {
                providerResults.append(result)
            }
        }

        diagnostics.append(contentsOf: providerResults.map(\.diagnostic))
        let ranked = ranker.rank(
            providerResults.flatMap(\.results),
            query: request.query,
            providerOrder: settings.providerOrder,
            maxResults: request.count ?? settings.maxMergedResults
        )
        let response = SearchResponse(
            query: request.query,
            results: ranked,
            diagnostics: diagnostics,
            cached: false,
            generatedAt: clock.now()
        )
        cache.store(response, for: cacheKey, ttlSeconds: settings.cacheTTLSeconds)
        if settings.globalCacheEnabled {
            globalCache.store(response, for: cacheKey, ttlSeconds: settings.cacheTTLSeconds)
        }
        return response
    }

    func searchAndExtract(_ request: SearchRequest) async -> SearchAndExtractResponse {
        let searchResponse = await search(request)
        let settings = request.settings ?? .defaults
        let top = searchResponse.results.prefix(min(3, searchResponse.results.count))
        var extractions: [PageExtractionResult] = []
        for result in top {
            extractions.append(await extractor.extract(PageExtractionRequest(url: result.url), settings: settings))
        }
        return SearchAndExtractResponse(search: searchResponse, extractions: extractions)
    }

    func providerStatus(settings: WebSearchSettings = .defaults) -> ProviderStatusResponse {
        let enabledIDs = Set(providers.filter { isEnabled($0.id, settings: settings) }.map(\.id))
        let diagnostics = providers.map { provider in
            ProviderDiagnostic(
                providerID: provider.id,
                state: enabledIDs.contains(provider.id) ? .ok : .disabled,
                message: enabledIDs.contains(provider.id) ? "Provider enabled" : "Provider disabled"
            )
        } + disabledDiagnostics(settings: settings)
        return ProviderStatusResponse(diagnostics: diagnostics, generatedAt: clock.now())
    }

    func clearCache() {
        cache.clear()
        globalCache.clear()
    }

    private func isEnabled(_ providerID: String, settings: WebSearchSettings) -> Bool {
        switch providerID {
        case "duckduckgo_lite": return settings.duckduckgoLiteEnabled
        case "wikipedia": return settings.wikipediaEnabled
        case "github": return settings.githubSearchEnabled
        case "stack_exchange": return settings.stackExchangeEnabled
        case "hacker_news": return settings.hackerNewsEnabled
        case "brave": return settings.braveEnabled
        case "tavily": return settings.tavilyEnabled
        case "firecrawl": return settings.firecrawlEnabled
        default: return false
        }
    }

    private func disabledDiagnostics(settings: WebSearchSettings) -> [ProviderDiagnostic] {
        []
    }
}

struct SearchAndExtractResponse: Codable, Sendable, Equatable {
    var search: SearchResponse
    var extractions: [PageExtractionResult]
}

struct ProviderStatusResponse: Codable, Sendable, Equatable {
    var diagnostics: [ProviderDiagnostic]
    var generatedAt: Date
}
