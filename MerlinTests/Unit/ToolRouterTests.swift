import XCTest
@testable import Merlin

@MainActor
final class ToolRouterTests: XCTestCase {

    func testDispatchesInParallel() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "echo_a", pattern: "*")
        memory.addAllowPattern(tool: "echo_b", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        router.register(name: "echo_a") { _ in "A" }
        router.register(name: "echo_b") { _ in "B" }

        let calls = [
            ToolCall(id: "1", type: "function", function: FunctionCall(name: "echo_a", arguments: "{}")),
            ToolCall(id: "2", type: "function", function: FunctionCall(name: "echo_b", arguments: "{}")),
        ]

        let results = await router.dispatch(calls)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].content, "A")
        XCTAssertEqual(results[1].content, "B")
    }

    func testDeniedToolReturnsError() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addDenyPattern(tool: "bad_tool", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let calls = [
            ToolCall(id: "x", type: "function", function: FunctionCall(name: "bad_tool", arguments: "{}"))
        ]

        let results = await router.dispatch(calls)
        XCTAssertTrue(results[0].isError)
    }

    func testScopedMCPToolsAreFilteredByActiveDomain() async {
        let memory = AuthMemory(storePath: "/dev/null")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let scoped = ToolDefinition(function: .init(name: "mcp:kicad:route_board", description: "Route board", parameters: JSONSchema(type: "object")))
        let unscoped = ToolDefinition(function: .init(name: "mcp:github:list_prs", description: "List PRs", parameters: JSONSchema(type: "object")))

        router.registerMCPTool(scoped, scopedToDomainID: ElectronicsDomain.defaultID) { _ in "ok" }
        router.registerMCPTool(unscoped) { _ in "ok" }

        XCTAssertEqual(
            router.mcpToolDefinitions(activeDomainIDs: SoftwareDomain.defaultActiveDomainIDs).map(\.function.name).sorted(),
            ["mcp:github:list_prs"]
        )
        XCTAssertEqual(
            Set(router.mcpToolDefinitions(activeDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]).map(\.function.name)),
            ["mcp:github:list_prs", "mcp:kicad:route_board"]
        )
        XCTAssertFalse(router.isAllowedMCPTool(named: "mcp:kicad:route_board", activeDomainIDs: SoftwareDomain.defaultActiveDomainIDs))
        XCTAssertTrue(router.isAllowedMCPTool(named: "mcp:kicad:route_board", activeDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]))
    }
}
