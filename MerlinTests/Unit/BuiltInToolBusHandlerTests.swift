import XCTest
@testable import Merlin

@MainActor
final class BuiltInToolBusHandlerTests: XCTestCase {
    func testRegisterAllToolsRegistersRoutesForModelVisibleBuiltIns() throws {
        let router = try makeRouter()
        registerAllTools(router: router)

        let registered = Set(router.registeredRoutes().map(\.toolName))
        let expected = Set(ToolDefinitions.all.map(\.function.name)).subtracting(["spawn_agent"])
        XCTAssertTrue(
            expected.isSubset(of: registered),
            "Missing routes: \(expected.subtracting(registered).sorted())"
        )
    }

    func testRoutesUseExpectedNamespacesAndScopes() throws {
        let router = try makeRouter()
        registerAllTools(router: router)

        XCTAssertEqual(router.route(for: "read_file")?.address.namespace, "builtin.files")
        XCTAssertEqual(router.route(for: "run_shell")?.address.namespace, "builtin.shell")
        XCTAssertEqual(router.route(for: "xcode_build")?.address.namespace, "builtin.xcode")
        XCTAssertEqual(router.route(for: "ui_click")?.address.namespace, "builtin.ui")
        XCTAssertEqual(router.route(for: "app_launch")?.address.namespace, "builtin.app")
        XCTAssertEqual(router.route(for: "write_file")?.requiredPermissionScope, .workspaceWrite)
        XCTAssertEqual(router.route(for: "read_file")?.requiredPermissionScope, .readOnly)
    }

    private func makeRouter() throws -> ToolRouter {
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-builtins-tests-\(UUID().uuidString)")
        )
        return ToolRouter(
            authGate: AuthGate(memory: AuthMemory(storePath: "/dev/null"), presenter: NullAuthPresenter()),
            workspaceRuntime: runtime
        )
    }
}
