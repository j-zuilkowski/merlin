# Phase 50a — Web Search Tool Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 49b complete: ThreadAutomations in place.

New surface introduced in phase 50b:
  - `BraveSearchClient` — actor; wraps Brave Search API REST calls
  - `BraveSearchClient(apiKey:)` — init
  - `BraveSearchClient.search(query:count:) async throws -> [BraveSearchResult]`
  - `BraveSearchResult` — struct: `title: String`, `url: String`, `description: String`
  - `WebSearchTool` — struct conforming to the tool execution pattern; calls BraveSearchClient
  - `WebSearchTool.execute(query: String) async throws -> String` — returns formatted result block
  - `ToolRegistry` registers WebSearchTool only when Brave API key is present in Keychain

TDD coverage:
  File 1 — WebSearchToolTests: execute with mock client returns formatted output,
           empty results returns empty message, execute propagates errors,
           result formatting includes title+url+description, ToolRegistry skips
           registration when no API key

---

## Write to: MerlinTests/Unit/WebSearchToolTests.swift

```swift
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
        // Builtins should NOT include web_search (requires API key)
        let hasSearch = await registry.contains(named: "web_search")
        XCTAssertFalse(hasSearch)
    }

    func test_registry_registersWebSearch_whenAPIKeyPresent() async {
        let registry = ToolRegistry()
        await registry.registerBuiltins()
        // Simulate API key present — register conditionally
        await registry.registerWebSearchIfAvailable(apiKey: "test-key")
        let hasSearch = await registry.contains(named: "web_search")
        XCTAssertTrue(hasSearch)
    }
}

// MARK: - Mock

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
        if let error { throw error }
        return results
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `BraveSearchClient`, `BraveSearchResult`, `WebSearchTool`,
`BraveSearchClientProtocol`, `ToolRegistry.registerWebSearchIfAvailable` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/WebSearchToolTests.swift
git commit -m "Phase 50a — WebSearchToolTests (failing)"
```
