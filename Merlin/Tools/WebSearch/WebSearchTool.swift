import Foundation

struct WebSearchTool: Sendable {
    private let client: any BraveSearchClientProtocol

    init(client: any BraveSearchClientProtocol) {
        self.client = client
    }

    func execute(query: String, count: Int = 10) async throws -> String {
        let results = try await client.search(query: query, count: count)
        guard results.isEmpty == false else {
            return "No results found for: \(query)"
        }

        return results.enumerated().map { index, result in
            """
            [\(index + 1)] \(result.title)
            URL: \(result.url)
            \(result.description)
            """
        }.joined(separator: "\n\n")
    }

    static var toolDefinition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "web_search",
                description: "Search the web using Brave Search. Returns titles, URLs, and descriptions.",
                parameters: .init(
                    type: "object",
                    properties: [
                        "query": .init(type: "string", description: "The search query"),
                        "count": .init(type: "integer", description: "Number of results (1-10, default 10)")
                    ],
                    required: ["query"]
                )
            )
        )
    }
}
