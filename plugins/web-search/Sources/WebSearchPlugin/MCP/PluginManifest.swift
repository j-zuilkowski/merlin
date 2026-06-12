import Foundation

enum PluginManifest {
    static func manifest() -> [String: Any] {
        [
            "id": "web-search",
            "display_name": "Web Search",
            "version": "1.0.0",
            "trust_tier": "tier2",
            "enabled": true,
            "domain_ids": [],
            "settings_schema": settingsSchema(),
            "capabilities": capabilities(),
            "tool_routes": toolRoutes(),
        ]
    }

    static func manifestText() -> String {
        JSON.objectString(manifest())
    }

    static func settingsSchema() -> [String: Any] {
        [
            "namespace": "plugin.web_search",
            "title": "Web Search",
            "fields": [
                field("duckduckgo_lite_enabled", "DuckDuckGo Lite", "boolean", boolDefault(true), false, "Enable DuckDuckGo lite/HTML search provider."),
                field("wikipedia_enabled", "Wikipedia", "boolean", boolDefault(true), false, "Enable Wikipedia API provider."),
                field("github_search_enabled", "GitHub Search", "boolean", boolDefault(true), false, "Enable GitHub Search API provider."),
                field("stack_exchange_enabled", "Stack Exchange", "boolean", boolDefault(true), false, "Enable Stack Exchange API provider."),
                field("hacker_news_enabled", "Hacker News", "boolean", boolDefault(true), false, "Enable Hacker News Algolia provider."),
                field("brave_enabled", "Brave", "boolean", boolDefault(false), false, "Optional managed Brave Search provider."),
                field("brave_api_key", "Brave API Key", "secret", nil, true, "Optional Brave credential."),
                field("tavily_enabled", "Tavily", "boolean", boolDefault(false), false, "Optional managed Tavily search provider."),
                field("tavily_api_key", "Tavily API Key", "secret", nil, true, "Optional Tavily credential."),
                field("firecrawl_enabled", "Firecrawl", "boolean", boolDefault(false), false, "Optional managed Firecrawl search provider."),
                field("firecrawl_api_key", "Firecrawl API Key", "secret", nil, true, "Optional Firecrawl credential."),
                field("provider_order", "Provider Order", "string", stringDefault("duckduckgo_lite,wikipedia,github,stack_exchange,hacker_news,brave,tavily,firecrawl"), false, "Merge/ranking precedence after scoring."),
                field("max_results_per_provider", "Max Results Per Provider", "integer", intDefault(10), false, "Per-provider result cap."),
                field("max_merged_results", "Max Merged Results", "integer", intDefault(10), false, "Final result cap returned to the model."),
                field("request_timeout_seconds", "Request Timeout Seconds", "integer", intDefault(15), false, "Network timeout per provider request."),
                field("rate_limit_backoff_seconds", "Rate Limit Backoff Seconds", "integer", intDefault(60), false, "Backoff after provider throttle/block diagnostics."),
                field("cache_ttl_seconds", "Cache TTL Seconds", "integer", intDefault(900), false, "Search-result cache TTL."),
                field("global_cache_enabled", "Global Cache", "boolean", boolDefault(false), false, "Share non-secret search cache entries across plugin instances."),
                field("extraction_max_bytes", "Extraction Max Bytes", "integer", intDefault(1_048_576), false, "Maximum fetched page bytes before extraction blocks."),
                field("webkit_extraction_enabled", "WebKit Extraction", "boolean", boolDefault(true), false, "Enable bounded WebKit fallback only after static extraction fails."),
                field("bot_policy_mode", "Bot Policy Mode", "string", stringDefault("respect"), false, "Advisory bot-policy handling: respect or ignore_advisory."),
                field("user_agent", "User Agent", "string", stringDefault(WebSearchSettings.defaults.userAgent), false, "HTTP user agent."),
            ],
        ]
    }

    static func capabilities() -> [[String: Any]] {
        [
            capability("plugin.web_search.search", "Web Search", "tool", "search", "externalSideEffect"),
            capability("plugin.web_search.extract_page", "Web Extract Page", "tool", "extract_page", "externalSideEffect"),
            capability("plugin.web_search.search_and_extract", "Web Search And Extract", "tool", "search_and_extract", "externalSideEffect"),
            capability("plugin.web_search.provider_status", "Web Provider Status", "tool", "provider_status", "readOnly"),
            capability("plugin.web_search.clear_cache", "Web Clear Cache", "tool", "clear_cache", "workspaceWrite"),
        ]
    }

    static func toolRoutes() -> [[String: Any]] {
        [
            route(ToolDefinitions.webSearch, "web_search", "search", "externalSideEffect"),
            route(ToolDefinitions.webExtractPage, "web_extract_page", "extract_page", "externalSideEffect"),
            route(ToolDefinitions.webSearchAndExtract, "web_search_and_extract", "search_and_extract", "externalSideEffect"),
            route(ToolDefinitions.webProviderStatus, "web_provider_status", "provider_status", "readOnly"),
            route(ToolDefinitions.webClearCache, "web_clear_cache", "clear_cache", "workspaceWrite"),
        ]
    }

    private static func field(_ key: String, _ label: String, _ kind: String, _ defaultValue: Any?, _ isSecret: Bool, _ help: String) -> [String: Any] {
        var object: [String: Any] = [
            "key": key,
            "label": label,
            "kind": kind,
            "isSecret": isSecret,
            "help": help,
        ]
        if let defaultValue {
            object["defaultValue"] = defaultValue
        }
        return object
    }

    private static func boolDefault(_ value: Bool) -> [String: Any] {
        ["boolean": ["_0": value]]
    }

    private static func intDefault(_ value: Int) -> [String: Any] {
        ["integer": ["_0": value]]
    }

    private static func stringDefault(_ value: String) -> [String: Any] {
        ["string": ["_0": value]]
    }

    private static func capability(_ id: String, _ displayName: String, _ kind: String, _ capability: String, _ scope: String) -> [String: Any] {
        [
            "id": id,
            "displayName": displayName,
            "kind": kind,
            "address": [
                "namespace": "plugin.web_search",
                "capability": capability,
            ],
            "requiredPermissionScope": scope,
        ]
    }

    private static func route(_ toolName: String, _ stableAlias: String, _ capability: String, _ scope: String) -> [String: Any] {
        [
            "tool_name": toolName,
            "stable_alias": stableAlias,
            "address": [
                "namespace": "plugin.web_search",
                "capability": capability,
            ],
            "required_permission_scope": scope,
        ]
    }
}
