import XCTest
@testable import WebSearchPlugin

final class MCPServerTests: XCTestCase {
    func testInitializeToolsListAndManifestResource() async throws {
        let server = makeServer()

        let initialize = await server.handleLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        XCTAssertTrue(initialize?.contains("web-search-plugin") == true)

        let tools = await server.handleLine(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#)
        XCTAssertTrue(tools?.contains("web_search") == true)
        XCTAssertTrue(tools?.contains("web_extract_page") == true)

        let resource = await server.handleLine(#"{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"merlin://plugin/manifest"}}"#)
        XCTAssertTrue(resource?.contains("plugin.web_search") == true)
    }

    func testProviderStatusAndSearchToolReturnJSONText() async throws {
        let server = makeServer()

        let status = await server.handleLine(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"web_provider_status","arguments":{}}}"#)
        XCTAssertTrue(status?.contains("duckduckgo_lite") == true)

        let search = await server.handleLine(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"web_search","arguments":{"query":"merlin"}}}"#)
        XCTAssertTrue(search?.contains("Example") == true)
    }

    func testInitializedRequestKeepsBridgeHandshakeMoving() async throws {
        let server = makeServer()

        let response = await server.handleLine(#"{"jsonrpc":"2.0","id":2,"method":"notifications/initialized","params":{}}"#)

        XCTAssertTrue(response?.contains(#""id":2"#) == true, response ?? "")
        XCTAssertTrue(response?.contains(#""error""#) == false, response ?? "")
    }

    private func makeServer() -> WebSearchMCPServer {
        let provider = StubProvider(id: "duckduckgo_lite", url: "https://example.com", title: "Example")
        let extractor = StubExtractor()
        return WebSearchMCPServer(
            coordinator: SearchCoordinator(providers: [provider], extractor: extractor),
            extractor: extractor
        )
    }
}
