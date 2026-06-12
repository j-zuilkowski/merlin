import Foundation

final class WebSearchMCPServer: @unchecked Sendable {
    private let coordinator: SearchCoordinator
    private let extractor: any PageExtractionProvider

    init(coordinator: SearchCoordinator, extractor: any PageExtractionProvider) {
        self.coordinator = coordinator
        self.extractor = extractor
    }

    static func production() -> WebSearchMCPServer {
        let httpClient = URLSessionHTTPClient()
        let extractor = BoundedFallbackPageExtractor(
            primary: URLSessionPageExtractor(httpClient: httpClient),
            fallback: WebKitPageExtractor()
        )
        let providers: [any SearchProvider] = [
            DuckDuckGoLiteProvider(httpClient: httpClient),
            WikipediaProvider(httpClient: httpClient),
            GitHubSearchProvider(httpClient: httpClient),
            StackExchangeProvider(httpClient: httpClient),
            HackerNewsProvider(httpClient: httpClient),
            BraveSearchProvider(httpClient: httpClient),
            TavilySearchProvider(httpClient: httpClient),
            FirecrawlSearchProvider(httpClient: httpClient),
        ]
        return WebSearchMCPServer(
            coordinator: SearchCoordinator(providers: providers, extractor: extractor),
            extractor: extractor
        )
    }

    func handleLine(_ line: String) async -> String? {
        guard let request = try? JSON.decoder.decode(MCPRequest.self, from: Data(line.utf8)) else {
            return MCPResponse.error(id: nil, code: -32700, message: "Parse error")
        }
        if request.method.hasPrefix("notifications/"), request.id == nil {
            return nil
        }
        do {
            let result = try await handle(request)
            return MCPResponse.result(id: request.id, result)
        } catch {
            return MCPResponse.error(id: request.id, code: -32000, message: String(describing: error))
        }
    }

    func runStdio() async {
        while let line = readLine() {
            guard let response = await handleLine(line) else { continue }
            print(response)
            fflush(stdout)
        }
    }

    private func handle(_ request: MCPRequest) async throws -> [String: Any] {
        switch request.method {
        case "initialize":
            return [
                "protocolVersion": "2024-11-05",
                "serverInfo": ["name": "web-search-plugin", "version": "1.0.0"],
                "capabilities": ["tools": [:], "resources": [:]],
            ]
        case "notifications/initialized":
            return [:]
        case "tools/list":
            return ["tools": ToolDefinitions.listTools()]
        case "tools/call":
            return try await callTool(params: request.params?.objectValue ?? [:])
        case "resources/read":
            return readResource(params: request.params?.objectValue ?? [:])
        default:
            throw MCPServerError.unknownMethod(request.method)
        }
    }

    private func callTool(params: [String: JSONValue]) async throws -> [String: Any] {
        guard let name = params["name"]?.stringValue else {
            throw MCPServerError.invalidParams("Missing tool name")
        }
        let arguments = params["arguments"]?.objectValue ?? [:]
        let text: String
        switch name {
        case ToolDefinitions.webSearch:
            let request = searchRequest(from: arguments)
            text = encodeText(await coordinator.search(request))
        case ToolDefinitions.webSearchAndExtract:
            let request = searchRequest(from: arguments)
            text = encodeText(await coordinator.searchAndExtract(request))
        case ToolDefinitions.webExtractPage:
            guard let url = arguments["url"]?.stringValue else {
                throw MCPServerError.invalidParams("Missing url")
            }
            let settings = settings(from: arguments["settings"]?.objectValue)
            text = encodeText(await extractor.extract(PageExtractionRequest(url: url, settings: settings), settings: settings))
        case ToolDefinitions.webProviderStatus:
            text = encodeText(coordinator.providerStatus(settings: settings(from: arguments["settings"]?.objectValue)))
        case ToolDefinitions.webClearCache:
            coordinator.clearCache()
            text = #"{"status":"ok","message":"cache cleared"}"#
        default:
            throw MCPServerError.unknownTool(name)
        }
        return [
            "content": [
                ["type": "text", "text": text],
            ],
        ]
    }

    private func readResource(params: [String: JSONValue]) -> [String: Any] {
        guard params["uri"]?.stringValue == "merlin://plugin/manifest" else {
            return ["contents": []]
        }
        return [
            "contents": [
                [
                    "uri": "merlin://plugin/manifest",
                    "mimeType": "application/json",
                    "text": PluginManifest.manifestText(),
                ],
            ],
        ]
    }

    private func searchRequest(from arguments: [String: JSONValue]) -> SearchRequest {
        SearchRequest(
            query: arguments["query"]?.stringValue ?? "",
            locale: arguments["locale"]?.stringValue,
            count: arguments["count"]?.intValue,
            freshnessHint: arguments["freshness_hint"]?.stringValue,
            allowedDomains: stringArray(arguments["allowed_domains"]),
            blockedDomains: stringArray(arguments["blocked_domains"]),
            providerOptions: [:],
            settings: settings(from: arguments["settings"]?.objectValue)
        )
    }

    private func settings(from object: [String: JSONValue]?) -> WebSearchSettings {
        guard let object else { return .defaults }
        var settings = WebSearchSettings.defaults
        settings.duckduckgoLiteEnabled = object["duckduckgo_lite_enabled"]?.boolValue ?? settings.duckduckgoLiteEnabled
        settings.wikipediaEnabled = object["wikipedia_enabled"]?.boolValue ?? settings.wikipediaEnabled
        settings.githubSearchEnabled = object["github_search_enabled"]?.boolValue ?? settings.githubSearchEnabled
        settings.stackExchangeEnabled = object["stack_exchange_enabled"]?.boolValue ?? settings.stackExchangeEnabled
        settings.hackerNewsEnabled = object["hacker_news_enabled"]?.boolValue ?? settings.hackerNewsEnabled
        settings.braveEnabled = object["brave_enabled"]?.boolValue ?? settings.braveEnabled
        settings.braveAPIKey = object["brave_api_key"]?.stringValue ?? settings.braveAPIKey
        settings.tavilyEnabled = object["tavily_enabled"]?.boolValue ?? settings.tavilyEnabled
        settings.tavilyAPIKey = object["tavily_api_key"]?.stringValue ?? settings.tavilyAPIKey
        settings.firecrawlEnabled = object["firecrawl_enabled"]?.boolValue ?? settings.firecrawlEnabled
        settings.firecrawlAPIKey = object["firecrawl_api_key"]?.stringValue ?? settings.firecrawlAPIKey
        if let order = object["provider_order"]?.stringValue {
            settings.providerOrder = order.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        settings.maxResultsPerProvider = object["max_results_per_provider"]?.intValue ?? settings.maxResultsPerProvider
        settings.maxMergedResults = object["max_merged_results"]?.intValue ?? settings.maxMergedResults
        settings.requestTimeoutSeconds = object["request_timeout_seconds"]?.intValue ?? settings.requestTimeoutSeconds
        settings.rateLimitBackoffSeconds = object["rate_limit_backoff_seconds"]?.intValue ?? settings.rateLimitBackoffSeconds
        settings.cacheTTLSeconds = object["cache_ttl_seconds"]?.intValue ?? settings.cacheTTLSeconds
        settings.globalCacheEnabled = object["global_cache_enabled"]?.boolValue ?? settings.globalCacheEnabled
        settings.extractionMaxBytes = object["extraction_max_bytes"]?.intValue ?? settings.extractionMaxBytes
        settings.webkitExtractionEnabled = object["webkit_extraction_enabled"]?.boolValue ?? settings.webkitExtractionEnabled
        if let mode = object["bot_policy_mode"]?.stringValue, let parsed = BotPolicyMode(rawValue: mode) {
            settings.botPolicyMode = parsed
        }
        settings.userAgent = object["user_agent"]?.stringValue ?? settings.userAgent
        return settings
    }

    private func stringArray(_ value: JSONValue?) -> [String] {
        guard case .array(let values)? = value else { return [] }
        return values.compactMap(\.stringValue)
    }

    private func encodeText<T: Encodable>(_ value: T) -> String {
        let data = (try? JSON.encoder.encode(value)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

enum MCPServerError: Error, CustomStringConvertible {
    case unknownMethod(String)
    case unknownTool(String)
    case invalidParams(String)

    var description: String {
        switch self {
        case .unknownMethod(let method): "Unknown MCP method: \(method)"
        case .unknownTool(let tool): "Unknown MCP tool: \(tool)"
        case .invalidParams(let message): message
        }
    }
}
