import XCTest
@testable import Merlin

@MainActor
final class ToolRouterBusDispatchTests: XCTestCase {
    func testDispatchUsesWorkspaceMessageBusRoute() async throws {
        let router = try makeRouter()
        router.register(
            name: "echo",
            namespace: "test.tools",
            capability: "echo",
            requiredScope: .readOnly
        ) { args in
            args
        }

        let result = await router.dispatch([ToolCall(
            id: "call-1",
            type: "function",
            function: FunctionCall(name: "echo", arguments: #"{"value":"ok"}"#)
        )]).first

        XCTAssertEqual(result?.content, #"{"value":"ok"}"#)
        XCTAssertFalse(result?.isError ?? true)
        XCTAssertEqual(router.route(for: "echo")?.address, WorkspaceMessageAddress(namespace: "test.tools", capability: "echo"))
    }

    func testUnknownToolUsesRouteNotFoundDiagnostic() async throws {
        let router = try makeRouter()
        let result = await router.dispatch([ToolCall(
            id: "call-1",
            type: "function",
            function: FunctionCall(name: "missing_tool", arguments: "{}")
        )]).first

        XCTAssertTrue(result?.isError ?? false)
        XCTAssertTrue(result?.content.contains("ROUTE_NOT_FOUND") == true)
    }

    func testFailedBusResponseRetriesOnce() async throws {
        let router = try makeRouter()
        var attempts = 0
        router.register(name: "flaky", namespace: "test.tools", capability: "flaky") { _ in
            attempts += 1
            if attempts == 1 {
                struct FlakyError: Error {}
                throw FlakyError()
            }
            return "ok"
        }

        let result = await router.dispatch([ToolCall(
            id: "call-1",
            type: "function",
            function: FunctionCall(name: "flaky", arguments: "{}")
        )]).first

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(result?.content, "ok")
        XCTAssertFalse(result?.isError ?? true)
    }

    func testBusErrorStatusesBecomeErrorResults() async throws {
        let router = try makeRouter()
        router.register(name: "write", namespace: "test.tools", capability: "write", requiredScope: .workspaceWrite) { _ in
            "written"
        }

        let unauthorized = await router.dispatch([ToolCall(
            id: "call-1",
            type: "function",
            function: FunctionCall(name: "write", arguments: "{}")
        )]).first

        XCTAssertTrue(unauthorized?.isError ?? false)
        XCTAssertTrue(unauthorized?.content.contains("UNAUTHORIZED_SCOPE") == true)
    }

    func testStagingStillPrecedesBusDispatchForFileMutations() async throws {
        let router = try makeRouter()
        let buffer = StagingBuffer()
        router.stagingBuffer = buffer
        router.permissionMode = .plan
        router.register(name: "write_file", namespace: "builtin.files", capability: "write_file", requiredScope: .workspaceWrite) { _ in
            XCTFail("staged writes must not reach the bus")
            return "unexpected"
        }

        let result = await router.dispatch([ToolCall(
            id: "call-1",
            type: "function",
            function: FunctionCall(name: "write_file", arguments: #"{"path":"/tmp/file.txt","content":"hello"}"#)
        )]).first

        XCTAssertFalse(result?.isError ?? true)
        let changes = await buffer.pendingChanges
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.path, "/tmp/file.txt")
    }

    private func makeRouter() throws -> ToolRouter {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-router-tests-\(UUID().uuidString)")
        )
        return ToolRouter(
            authGate: AuthGate(memory: memory, presenter: NullAuthPresenter()),
            workspaceRuntime: runtime,
            originProvider: { route in
                WorkspaceMessageOrigin(
                    workspaceID: runtime.workspaceID,
                    sessionID: nil,
                    agentID: nil,
                    subagentID: nil,
                    worktreeID: nil,
                    subagentDepth: 0,
                    permissionScope: route.requiredPermissionScope == .readOnly ? .readOnly : .readOnly,
                    activeDomainIDs: ["software"]
                )
            }
        )
    }
}
