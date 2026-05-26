import XCTest
@testable import KiCadMCPKit

/// Exercises the MCP protocol core through `MCPServer.handle(_:)` — one message line
/// in, one response line out.
final class MCPServerCoreTests: XCTestCase {

    func testInitializeHandshake() async {
        let server = MCPServer()
        let response = await server.handle(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        let unwrapped = try? XCTUnwrap(response)
        XCTAssertNotNil(unwrapped)
        XCTAssertTrue(response?.contains("\"serverInfo\"") == true)
        XCTAssertTrue(response?.contains("merlin-kicad-mcp") == true)
        XCTAssertTrue(response?.contains("\"protocolVersion\"") == true)
    }

    func testParseErrorOnMalformedInput() async {
        let server = MCPServer()
        let response = await server.handle("this is not json")
        XCTAssertTrue(response?.contains("-32700") == true)
    }

    func testMethodNotFound() async {
        let server = MCPServer()
        let response = await server.handle(
            #"{"jsonrpc":"2.0","id":7,"method":"does/not/exist"}"#)
        XCTAssertTrue(response?.contains("-32601") == true)
    }

    func testNotificationReturnsNil() async {
        let server = MCPServer()
        let response = await server.handle(
            #"{"jsonrpc":"2.0","method":"notifications/something"}"#)
        XCTAssertNil(response, "a message with no id is a notification — no reply")
    }

    func testEmptyLineReturnsNil() async {
        let server = MCPServer()
        let response = await server.handle("   ")
        XCTAssertNil(response)
    }

    func testToolsListExposesKiCadTools() async {
        let server = MCPServer()
        let response = await server.handle(
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#)
        XCTAssertTrue(response?.contains("kicad_check_version") == true)
        XCTAssertTrue(response?.contains("kicad_compile_project") == true)
        XCTAssertTrue(response?.contains("\"inputSchema\"") == true)
    }

    func testToolsCallReturnsContent() async {
        let server = MCPServer()
        let response = await server.handle(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"kicad_check_version","arguments":{"kicad_cli_path":"/nonexistent","required_major":10}}}"#)
        XCTAssertTrue(response?.contains("\"content\"") == true)
        XCTAssertTrue(response?.contains("\"text\"") == true)
    }

    func testToolsCallUnknownToolErrors() async {
        let server = MCPServer()
        let response = await server.handle(
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"kicad_nope","arguments":{}}}"#)
        XCTAssertTrue(response?.contains("-32601") == true)
    }

    func testResourcesListExposesDomainManifest() async {
        let server = MCPServer()
        let response = await server.handle(
            #"{"jsonrpc":"2.0","id":5,"method":"resources/list","params":{}}"#
        )
        XCTAssertTrue(response?.contains("merlin://domain/manifest") == true)
        XCTAssertTrue(response?.contains("\"mimeType\":\"application/json\"") == true)
    }

    func testResourcesReadReturnsDomainManifestJSON() async throws {
        let server = MCPServer()
        let response = await server.handle(
            #"{"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"merlin://domain/manifest"}}"#
        )
        let unwrapped = try XCTUnwrap(response)
        XCTAssertTrue(unwrapped.contains("\"contents\""))
        XCTAssertTrue(unwrapped.contains("\\\"mcpToolNames\\\""))
        XCTAssertTrue(unwrapped.contains("kicad_check_version"))
        XCTAssertTrue(unwrapped.contains("\\\"id\\\":\\\"kicad\\\""))
    }
}
