import XCTest
@testable import Merlin

final class MCPBridgeTransportSelectionTests: XCTestCase {

    func test_defaultTransportKindKeepsStdio() throws {
        let config = try decodeServerConfig(#"{"command":"run-mcp","args":[],"env":{}}"#)
        XCTAssertEqual(MCPBridge.resolvedTransportKind(for: config), .stdio)
    }

    func test_httpTransportUsesConfiguredURL() throws {
        let config = try decodeServerConfig(
            #"{"command":"run-mcp","args":[],"env":{},"transport":"http","url":"http://example.test/mcp"}"#
        )
        XCTAssertEqual(config.transportKind, .http)
        XCTAssertEqual(config.transportURL, "http://example.test/mcp")
        XCTAssertEqual(MCPBridge.resolvedTransportKind(for: config), .http)
    }

    func test_sseTransportUsesConfiguredURL() throws {
        let config = try decodeServerConfig(
            #"{"command":"run-mcp","args":[],"env":{},"transport":"sse","url":"http://example.test/events"}"#
        )
        XCTAssertEqual(config.transportKind, .sse)
        XCTAssertEqual(config.transportURL, "http://example.test/events")
        XCTAssertEqual(MCPBridge.resolvedTransportKind(for: config), .sse)
    }

    func test_unknownTransportValueFailsValidationBeforeLaunch() {
        XCTAssertThrowsError(
            try decodeServerConfig(#"{"command":"run-mcp","transport":"gopher"}"#
            )
        )
    }

    private func decodeServerConfig(_ json: String) throws -> MCPServerConfig {
        try JSONDecoder().decode(MCPServerConfig.self, from: Data(json.utf8))
    }
}
