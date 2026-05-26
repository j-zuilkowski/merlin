import XCTest

final class DirectRouteEliminationTests: XCTestCase {
    func testToolRouterHasNoProductionDirectHandlerDictionaries() throws {
        let source = try String(contentsOfFile: repoPath("Merlin/Engine/ToolRouter.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("private var handlers:"))
        XCTAssertFalse(source.contains("private var mcpHandlers:"))
        XCTAssertFalse(source.contains("let handler: ((String) async throws -> String)?"))
        XCTAssertFalse(source.contains("try await handler(call.function.arguments)"))
    }

    func testMCPBridgeRegistersBusBackedRoutes() throws {
        let source = try String(contentsOfFile: repoPath("Merlin/MCP/MCPBridge.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("registerMCPTool"))
        XCTAssertTrue(source.contains("WorkspaceMessageBus") || source.contains("MCPMessageTransport"))
        XCTAssertFalse(source.contains("mcpHandlers"))
    }

    private func repoPath(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
            .path
    }
}
