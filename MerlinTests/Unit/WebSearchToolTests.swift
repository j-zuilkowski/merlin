import XCTest
@testable import Merlin

final class WebSearchToolTests: XCTestCase {

    // MARK: - Result formatting

    func test_execute_formatsResults() async throws {
        let mockClient = MockBraveSearchClient(results: [
            BraveSearchResult(title: "Swift Docs", url: "https://swift.org", description: "Official Swift docs"),
            BraveSearchResult(title: "Hacking with Swift", url: "https://hackingwithswift.com", description: "Tutorials")
        ])
        let tool = WebSearchTool(client: mockClient)
        let output = try await tool.execute(query: "swift async await")
        XCTAssertTrue(output.contains("Swift Docs"))
        XCTAssertTrue(output.contains("https://swift.org"))
        XCTAssertTrue(output.contains("Official Swift docs"))
        XCTAssertTrue(output.contains("Hacking with Swift"))
    }

    func test_execute_emptyResults_returnsNoResultsMessage() async throws {
        let mockClient = MockBraveSearchClient(results: [])
        let tool = WebSearchTool(client: mockClient)
        let output = try await tool.execute(query: "xyzzyplugh")
        XCTAssertTrue(output.lowercased().contains("no results"))
    }

    func test_execute_propagatesClientError() async {
        let mockClient = MockBraveSearchClient(error: URLError(.badServerResponse))
        let tool = WebSearchTool(client: mockClient)
        do {
            _ = try await tool.execute(query: "any")
            XCTFail("Expected error to propagate")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func test_execute_receivesQueryFromCaller() async throws {
        let mockClient = MockBraveSearchClient(results: [])
        let tool = WebSearchTool(client: mockClient)
        _ = try? await tool.execute(query: "specific query text")
        XCTAssertEqual(mockClient.lastQuery, "specific query text")
    }

    func test_execute_defaultCount_is10() async throws {
        let mockClient = MockBraveSearchClient(results: [])
        let tool = WebSearchTool(client: mockClient)
        _ = try? await tool.execute(query: "test")
        XCTAssertEqual(mockClient.lastCount, 10)
    }

    // MARK: - ToolRegistry integration

    func test_registry_doesNotRegisterWebSearch_whenNoAPIKey() async {
        let registry = ToolRegistry()
        await registry.registerBuiltins()
        let hasSearch = await registry.contains(named: "web_search")
        XCTAssertFalse(hasSearch)
    }

    func test_registry_registersWebSearch_whenAPIKeyPresent() async {
        let registry = ToolRegistry()
        await registry.registerBuiltins()
        await registry.registerWebSearchIfAvailable(apiKey: "test-key")
        let hasSearch = await registry.contains(named: "web_search")
        XCTAssertTrue(hasSearch)
    }
}

final class MockBraveSearchClient: BraveSearchClientProtocol, @unchecked Sendable {
    private let results: [BraveSearchResult]
    private let error: Error?
    private(set) var lastQuery: String?
    private(set) var lastCount: Int?

    init(results: [BraveSearchResult] = [], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func search(query: String, count: Int) async throws -> [BraveSearchResult] {
        lastQuery = query
        lastCount = count
        if let error {
            throw error
        }
        return results
    }
}
