# Phase 50b — Web Search Tool Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 50a complete: failing tests in place.

New files:
  - `Merlin/Tools/WebSearch/BraveSearchClient.swift`
  - `Merlin/Tools/WebSearch/WebSearchTool.swift`

Edit:
  - `Merlin/Tools/ToolRegistry.swift` — add `registerWebSearchIfAvailable(apiKey:)` method

Provider: Brave Search API (https://api.search.brave.com/res/v1/web/search)
API key stored in Keychain. Tool absent from ToolRegistry when key is not configured.
Free tier: 2,000 queries/month.

---

## Write to: Merlin/Tools/WebSearch/BraveSearchClient.swift

```swift
import Foundation

struct BraveSearchResult: Sendable {
    let title: String
    let url: String
    let description: String
}

// Protocol allows mock injection in tests.
protocol BraveSearchClientProtocol: Sendable {
    func search(query: String, count: Int) async throws -> [BraveSearchResult]
}

actor BraveSearchClient: BraveSearchClientProtocol {

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func search(query: String, count: Int = 10) async throws -> [BraveSearchResult] {
        var comps = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(min(count, 20)))
        ]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item -> BraveSearchResult? in
            guard let title = item["title"] as? String,
                  let url   = item["url"] as? String else { return nil }
            let desc = item["description"] as? String ?? ""
            return BraveSearchResult(title: title, url: url, description: desc)
        }
    }
}
```

---

## Write to: Merlin/Tools/WebSearch/WebSearchTool.swift

```swift
import Foundation

struct WebSearchTool: Sendable {

    private let client: any BraveSearchClientProtocol

    init(client: any BraveSearchClientProtocol) {
        self.client = client
    }

    func execute(query: String, count: Int = 10) async throws -> String {
        let results = try await client.search(query: query, count: count)
        guard !results.isEmpty else {
            return "No results found for: \(query)"
        }
        return results.enumerated().map { i, r in
            """
            [\(i + 1)] \(r.title)
            URL: \(r.url)
            \(r.description)
            """
        }.joined(separator: "\n\n")
    }

    // ToolDefinition for registration in ToolRegistry
    static var toolDefinition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "web_search",
                description: "Search the web using Brave Search. Returns titles, URLs, and descriptions.",
                parameters: .init(
                    type: "object",
                    properties: [
                        "query": ["type": "string", "description": "The search query"],
                        "count": ["type": "integer", "description": "Number of results (1-10, default 10)"]
                    ],
                    required: ["query"]
                )
            )
        )
    }
}
```

---

## Edit: Merlin/Tools/ToolRegistry.swift

Add the conditional registration method after the existing `reset()` method:

```swift
// Registers the web_search tool only when an API key is available.
// Called during app launch after Keychain is loaded.
func registerWebSearchIfAvailable(apiKey: String) {
    guard !apiKey.isEmpty else { return }
    let def = WebSearchTool.toolDefinition
    register(def)
}
```

---

## Integration note

In `MerlinApp.swift` (or wherever AppSettings is initialized), after loading the API key from Keychain:

```swift
let braveKey = KeychainStore.shared.string(for: .braveAPIKey) ?? ""
await ToolRegistry.shared.registerWebSearchIfAvailable(apiKey: braveKey)
```

Add `braveAPIKey` case to the Keychain key enum used elsewhere in the project.

In `AgenticEngine.handleToolCall(_:)`, detect the `"web_search"` tool name and route to
`WebSearchTool(client: BraveSearchClient(apiKey: braveKey)).execute(query:)`.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all WebSearchToolTests pass.

## Commit
```bash
git add Merlin/Tools/WebSearch/BraveSearchClient.swift \
        Merlin/Tools/WebSearch/WebSearchTool.swift \
        Merlin/Tools/ToolRegistry.swift
git commit -m "Phase 50b — WebSearchTool (Brave Search API, conditional registration)"
```
