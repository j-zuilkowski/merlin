import XCTest
@testable import Merlin

@MainActor
final class KiCadMCPToolingTests: XCTestCase {

    func test_parseMajorVersion_extracts10() {
        XCTAssertEqual(KiCadVersionGate.parseMajorVersion(from: "KiCad Version: 10.0.1"), 10)
    }

    func test_evaluate_blocksWhenMajorVersionTooLow() {
        let decision = KiCadVersionGate.evaluate(versionOutput: "KiCad Version: 9.0.0", requiredMajor: 10)
        XCTAssertEqual(decision.status, .blockedVersion)
    }

    func test_executor_blocksWhenServerUnavailable() async throws {
        let config = KiCadMCPServerConfig(
            serverPath: "/tmp/missing-kicad-server",
            kicadCLIPath: "/usr/local/bin/kicad-cli",
            freeRoutingPath: "/usr/local/bin/freerouting",
            requiredToolNames: ["kicad_check_version"]
        )
        let executor = KiCadMCPToolExecutor(config: config, probe: .unavailable)

        let result = try await executor.execute(toolName: "kicad_check_version", arguments: [:])

        XCTAssertEqual(result.status, .blockedTooling)
        XCTAssertTrue(result.warnings.contains(where: { $0.code == "KICAD_MCP_UNAVAILABLE" }))
    }

    func test_executor_blocksWhenRequiredToolMissing() async throws {
        let config = KiCadMCPServerConfig(
            serverPath: "/tmp/kicad-mcp-server",
            kicadCLIPath: "/usr/local/bin/kicad-cli",
            freeRoutingPath: "/usr/local/bin/freerouting",
            requiredToolNames: ["kicad_export_fab"]
        )
        let executor = KiCadMCPToolExecutor(
            config: config,
            probe: .available(tools: ["kicad_check_version", "kicad_route_pass"])
        )

        let result = try await executor.execute(toolName: "kicad_export_fab", arguments: [:])
        XCTAssertEqual(result.status, .blockedTooling)
    }

    func test_routerRegistration_registersCoreKicadTools() async {
        let memory = AuthMemory(storePath: "/tmp/auth-kicad-mcp-tooling-tests.json")
        let router = ToolRouter(authGate: AuthGate(memory: memory, presenter: NullAuthPresenter()))
        router.permissionMode = .autoAccept

        router.registerKiCadTools(executor: FakeKiCadExecutor())

        let required = [
            "kicad_check_version",
            "kicad_ingest_schematic",
            "kicad_route_pass",
            "kicad_export_fab",
        ]

        let calls = required.enumerated().map { index, name in
            ToolCall(
                id: "kicad-\(index)",
                type: "function",
                function: FunctionCall(name: name, arguments: "{}")
            )
        }

        let results = await router.dispatch(calls)
        XCTAssertEqual(results.count, required.count)
        XCTAssertFalse(results.contains(where: \.isError))

        for result in results {
            let data = result.content.data(using: .utf8)
            XCTAssertNotNil(data)
            let decoded = try? JSONDecoder().decode(KiCadToolResult.self, from: data ?? Data())
            XCTAssertNotNil(decoded)
        }
    }
}

private struct FakeKiCadExecutor: KiCadToolExecutor {
    func execute(toolName: String, arguments: [String: Any]) async throws -> KiCadToolResult {
        KiCadToolResult(
            status: .complete,
            artifacts: [ArtifactRef(path: "/tmp/\(toolName).json", kind: "report")],
            nextActions: []
        )
    }
}
