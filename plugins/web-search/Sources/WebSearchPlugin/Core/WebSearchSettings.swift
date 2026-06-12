import Foundation

enum BotPolicyMode: String, Codable, Sendable, Equatable {
    case respect
    case ignoreAdvisory = "ignore_advisory"
}

struct WebSearchSettings: Codable, Sendable, Equatable {
    var duckduckgoLiteEnabled: Bool = true
    var wikipediaEnabled: Bool = true
    var githubSearchEnabled: Bool = true
    var stackExchangeEnabled: Bool = true
    var hackerNewsEnabled: Bool = true
    var braveEnabled: Bool = false
    var braveAPIKey: String?
    var tavilyEnabled: Bool = false
    var tavilyAPIKey: String?
    var firecrawlEnabled: Bool = false
    var firecrawlAPIKey: String?
    var providerOrder: [String] = ["duckduckgo_lite", "wikipedia", "github", "stack_exchange", "hacker_news", "brave", "tavily", "firecrawl"]
    var maxResultsPerProvider: Int = 10
    var maxMergedResults: Int = 10
    var requestTimeoutSeconds: Int = 15
    var rateLimitBackoffSeconds: Int = 60
    var cacheTTLSeconds: Int = 900
    var globalCacheEnabled: Bool = false
    var extractionMaxBytes: Int = 1_048_576
    var webkitExtractionEnabled: Bool = true
    var botPolicyMode: BotPolicyMode = .respect
    var userAgent: String = "Merlin-WebSearchPlugin/1.0"

    static let defaults = WebSearchSettings()
}
