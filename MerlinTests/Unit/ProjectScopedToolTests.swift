import XCTest
@testable import Merlin

@MainActor
final class ProjectScopedToolTests: XCTestCase {
    func testRunShellDefaultsToProjectRoot() async throws {
        let project = try makeProject()
        let router = try makeRouter(projectRoot: project.path)
        registerAllTools(router: router, defaultProjectPath: project.path)

        let result = await dispatch(
            router,
            name: "run_shell",
            arguments: #"{"command":"pwd"}"#
        )

        XCTAssertFalse(result.isError, result.content)
        XCTAssertTrue(result.content.contains(project.path), result.content)
    }

    func testListDirectoryDotResolvesToProjectRoot() async throws {
        let project = try makeProject(files: ["Cargo.toml": "[workspace]\n"])
        let router = try makeRouter(projectRoot: project.path)
        registerAllTools(router: router, defaultProjectPath: project.path)

        let result = await dispatch(
            router,
            name: "list_directory",
            arguments: #"{"path":".","recursive":false}"#
        )

        XCTAssertFalse(result.isError, result.content)
        XCTAssertTrue(result.content.contains("Cargo.toml"), result.content)
    }

    func testReadFileRelativePathResolvesToProjectRoot() async throws {
        let project = try makeProject(files: ["src/lib.rs": "pub fn ok() {}\n"])
        let router = try makeRouter(projectRoot: project.path)
        registerAllTools(router: router, defaultProjectPath: project.path)

        let result = await dispatch(
            router,
            name: "read_file",
            arguments: #"{"path":"src/lib.rs"}"#
        )

        XCTAssertFalse(result.isError, result.content)
        XCTAssertTrue(result.content.contains("pub fn ok"), result.content)
    }

    func testReadFileMissingAbsoluteSpecPathFallsBackToProjectSpec() async throws {
        let project = try makeProject(files: ["spec.md": "Authoritative project requirements\n"])
        let router = try makeRouter(projectRoot: project.path)
        registerAllTools(router: router, defaultProjectPath: project.path)

        let result = await dispatch(
            router,
            name: "read_file",
            arguments: #"{"path":"/Users/merlin/Documents/spec.md"}"#
        )

        XCTAssertFalse(result.isError, result.content)
        XCTAssertTrue(result.content.contains("Authoritative project requirements"), result.content)
        XCTAssertTrue(result.content.contains("corrected to current project root"), result.content)
        XCTAssertTrue(result.content.contains(project.path), result.content)
    }

    func testOutsideProjectAbsolutePathReturnsDiagnostic() async throws {
        let project = try makeProject(files: ["Cargo.toml": "[workspace]\n"])
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try "outside".write(to: outside.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let router = try makeRouter(projectRoot: project.path)
        registerAllTools(router: router, defaultProjectPath: project.path)

        let result = await dispatch(
            router,
            name: "list_directory",
            arguments: #"{"path":"\#(outside.path)","recursive":false}"#
        )

        XCTAssertFalse(result.isError, result.content)
        XCTAssertTrue(result.content.contains("outside current project root"), result.content)
        XCTAssertTrue(result.content.contains(project.path), result.content)
    }

    func testSystemPromptMarksCurrentProjectRootAsAuthoritative() async throws {
        let project = try makeProject()
        let engine = AgenticEngine()
        engine.currentProjectPath = project.path

        let prompt = await engine.buildSystemPromptForTesting()

        XCTAssertTrue(prompt.contains("AUTHORITATIVE PROJECT ROOT"), prompt)
        XCTAssertTrue(prompt.contains(project.path), prompt)
    }

    private func dispatch(_ router: ToolRouter, name: String, arguments: String) async -> ToolResult {
        await router.dispatch([
            ToolCall(id: "call-1", type: "function", function: FunctionCall(name: name, arguments: arguments))
        ]).first ?? ToolResult(toolCallId: "missing", content: "missing result", isError: true)
    }

    private func makeRouter(projectRoot: String) throws -> ToolRouter {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: projectRoot, isDirectory: true),
            merlinHomeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("merlin-project-scoped-tools-\(UUID().uuidString)")
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
                    permissionScope: route.requiredPermissionScope,
                    activeDomainIDs: ["software"]
                )
            }
        ).withAutoAccept()
    }

    private func makeProject(files: [String: String] = [:]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-scoped-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        for (relativePath, content) in files {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }
}

private extension ToolRouter {
    func withAutoAccept() -> ToolRouter {
        permissionMode = .autoAccept
        return self
    }
}
