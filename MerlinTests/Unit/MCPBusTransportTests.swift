import XCTest
@testable import Merlin

@MainActor
final class MCPBusTransportTests: XCTestCase {
    func testRegisterMCPToolCreatesBusRouteUnderServerNamespace() throws {
        let router = try makeRouter()
        let definition = ToolDefinition(function: .init(
            name: "mcp:github:list_issues",
            description: "List issues",
            parameters: JSONSchema(type: "object")
        ))

        router.registerMCPTool(definition) { _ in "ok" }

        XCTAssertEqual(router.route(for: "mcp:github:list_issues")?.address.namespace, "mcp.github")
        XCTAssertEqual(router.route(for: "mcp:github:list_issues")?.requiredPermissionScope, .externalSideEffect)
    }

    func testUnregisterMCPToolRemovesRouteAndDefinition() throws {
        let router = try makeRouter()
        let definition = ToolDefinition(function: .init(
            name: "mcp:github:list_issues",
            description: "List issues",
            parameters: JSONSchema(type: "object")
        ))

        router.registerMCPTool(definition) { _ in "ok" }
        router.unregisterMCPTools(named: ["mcp:github:list_issues"])

        XCTAssertNil(router.route(for: "mcp:github:list_issues"))
        XCTAssertTrue(router.mcpToolDefinitions().isEmpty)
    }

    private func makeRouter() throws -> ToolRouter {
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-mcpbus-tests-\(UUID().uuidString)")
        )
        return ToolRouter(
            authGate: AuthGate(memory: AuthMemory(storePath: "/dev/null"), presenter: NullAuthPresenter()),
            workspaceRuntime: runtime
        )
    }
}
