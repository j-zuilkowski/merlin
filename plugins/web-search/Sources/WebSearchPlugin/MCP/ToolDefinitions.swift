import Foundation

enum ToolDefinitions {
    static let webSearch = "web_search"
    static let webExtractPage = "web_extract_page"
    static let webSearchAndExtract = "web_search_and_extract"
    static let webProviderStatus = "web_provider_status"
    static let webClearCache = "web_clear_cache"

    static func listTools() -> [[String: Any]] {
        [
            tool(
                name: webSearch,
                description: "Search enabled web providers and return merged cited results plus diagnostics.",
                properties: [
                    "query": ["type": "string", "description": "Search query"],
                    "count": ["type": "integer", "description": "Optional final result cap"],
                    "allowed_domains": ["type": "array", "items": ["type": "string"]],
                    "blocked_domains": ["type": "array", "items": ["type": "string"]],
                ],
                required: ["query"]
            ),
            tool(
                name: webExtractPage,
                description: "Fetch one URL and extract readable text with source metadata.",
                properties: [
                    "url": ["type": "string", "description": "URL to extract"],
                ],
                required: ["url"]
            ),
            tool(
                name: webSearchAndExtract,
                description: "Search, select top results, extract pages, and return grounded snippets.",
                properties: [
                    "query": ["type": "string", "description": "Search query"],
                    "count": ["type": "integer", "description": "Optional final result cap"],
                ],
                required: ["query"]
            ),
            tool(
                name: webProviderStatus,
                description: "Report provider health, cache/backoff state, and diagnostics.",
                properties: [:],
                required: []
            ),
            tool(
                name: webClearCache,
                description: "Clear plugin search and extraction caches for the workspace.",
                properties: [:],
                required: []
            ),
        ]
    }

    private static func tool(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
            ],
        ]
    }
}
