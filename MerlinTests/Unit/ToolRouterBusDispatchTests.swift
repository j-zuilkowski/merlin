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

    func testBlockedElectronicsBusResponsePreservesPayloadAndArtifactsAsNormalToolResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-blocked-electronics-route-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let merlinHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-blocked-electronics-home-\(UUID().uuidString)", isDirectory: true)
        let runtime = try WorkspaceRuntime(rootURL: root, merlinHomeURL: merlinHome)
        let plugin = ElectronicsRuntimePlugin()
        try await plugin.register(into: runtime)
        let router = try makeRouter(rootURL: root, runtime: runtime, grantRouteScope: true)
        router.permissionMode = .autoAccept
        router.registerWorkspaceCapabilityTools(plugin.metadata.capabilities)

        let result = await router.dispatch([ToolCall(
            id: "call-1",
            type: "function",
            function: FunctionCall(name: "kicad_select_components", arguments: "{}")
        )]).first

        let content = try XCTUnwrap(result?.content)
        XCTAssertFalse(result?.isError ?? true)
        XCTAssertTrue(content.contains(#""status":"BLOCKED_TOOLING""#), content)
        XCTAssertTrue(content.contains("BLOCKED_ARTIFACT"), content)
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

    func testReadOnlyFileRoutesHaveAuthorizationHeadroom() async throws {
        let router = try makeRouter()
        for toolName in ["read_file", "list_directory", "search_files"] {
            router.register(name: toolName) { _ in "{}" }
            guard let route = router.route(for: toolName) else {
                XCTFail("Missing route for \(toolName)")
                continue
            }
            XCTAssertFalse(
                route.timeout < .seconds(120),
                "\(toolName) must leave enough time for GUI workspace routing and macOS file authorization"
            )
        }
    }

    func testElectronicsCatalogRoutesHaveLongRunningTimeouts() throws {
        let router = try makeRouter()
        router.registerWorkspaceCapabilityTools(ElectronicsRuntimePlugin().metadata.capabilities)

        XCTAssertEqual(router.route(for: "kicad_select_components")?.timeout, .seconds(420))
        XCTAssertEqual(router.route(for: "kicad_assign_footprints")?.timeout, .seconds(420))
        XCTAssertEqual(router.route(for: "kicad_compile_project")?.timeout, .seconds(420))
        XCTAssertEqual(router.route(for: "kicad_export_fab")?.timeout, .seconds(420))
        XCTAssertEqual(router.route(for: "workflow.requirements_to_pcb")?.timeout, .seconds(420))
    }

    func testReadFileBuiltInRouteReturnsThroughWorkspaceBus() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-read-file-route-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("spec.md")
        try "hello\nworld\n".write(to: file, atomically: true, encoding: .utf8)
        let router = try makeRouter(rootURL: root)
        registerAllTools(router: router, defaultProjectPath: root.path)

        let result = await router.dispatch([ToolCall(
            id: "call-1",
            type: "function",
            function: FunctionCall(name: "read_file", arguments: #"{"path":"spec.md"}"#)
        )]).first

        XCTAssertFalse(result?.isError ?? true)
        XCTAssertTrue(result?.content.contains("1\thello") == true, result?.content ?? "")
        XCTAssertTrue(result?.content.contains("2\tworld") == true, result?.content ?? "")
    }

    private func makeRouter() throws -> ToolRouter {
        try makeRouter(rootURL: URL(fileURLWithPath: "/tmp"))
    }

    private func makeRouter(rootURL: URL) throws -> ToolRouter {
        let runtime = try WorkspaceRuntime(
            rootURL: rootURL,
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-router-tests-\(UUID().uuidString)")
        )
        return try makeRouter(rootURL: rootURL, runtime: runtime)
    }

    private func makeRouter(rootURL: URL, runtime: WorkspaceRuntime, grantRouteScope: Bool = false) throws -> ToolRouter {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
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
                    permissionScope: grantRouteScope ? route.requiredPermissionScope : .readOnly,
                    activeDomainIDs: ["software"]
                )
            }
        )
    }
}
