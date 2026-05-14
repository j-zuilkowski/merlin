import XCTest
@testable import Merlin

@MainActor
final class KiCadMCPRealExecutorTests: XCTestCase {

    func test_executorCallsClientWithSameToolNameAndArguments() async throws {
        let client = FakeKiCadMCPClient(responseJSON: Self.makeResultJSON(
            KiCadToolResult(status: .complete)
        ))
        let executor = KiCadMCPToolExecutor(
            config: Self.makeConfig(requiredToolNames: ["kicad_route_pass"]),
            probe: .available(tools: ["kicad_route_pass"]),
            client: client
        )

        let arguments: [String: Any] = [
            "board": "demo.kicad_pcb",
            "layers": 4
        ]
        _ = try await executor.execute(toolName: "kicad_route_pass", arguments: arguments)

        XCTAssertEqual(client.calls.count, 1)
        XCTAssertEqual(client.calls.first?.toolName, "kicad_route_pass")
        XCTAssertEqual(Self.canonicalJSONString(from: client.calls.first?.arguments ?? [:]), Self.canonicalJSONString(from: arguments))
    }

    func test_clientJSONResponseMapsToKiCadToolResult() async throws {
        let expected = KiCadToolResult(
            status: .complete,
            artifacts: [
                ArtifactRef(path: "/tmp/kicad/fab.drl", kind: "drill"),
                ArtifactRef(path: "/tmp/kicad/fab.gbr", kind: "gerber")
            ],
            warnings: [
                KiCadWarning(
                    code: "KICAD_REAL_EXECUTOR_OK",
                    message: "Real executor returned client payload.",
                    affectedRefs: ["/tmp/kicad/fab.drl"],
                    suggestedAction: nil
                )
            ],
            metrics: ["artifact_count": 2]
        )
        let client = FakeKiCadMCPClient(responseJSON: Self.makeResultJSON(expected))
        let executor = KiCadMCPToolExecutor(
            config: Self.makeConfig(),
            probe: .available(tools: ["kicad_export_fab"]),
            client: client
        )

        let result = try await executor.execute(toolName: "kicad_export_fab", arguments: [:])

        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.artifacts, expected.artifacts)
    }

    func test_versionGateBlocksBeforeClientExecution() async throws {
        let client = FakeKiCadMCPClient(responseJSON: Self.makeResultJSON(KiCadToolResult(status: .complete)))
        let executor = KiCadMCPToolExecutor(
            config: Self.makeConfig(requiredToolNames: ["kicad_route_pass"]),
            probe: KiCadMCPToolingStatus.available(
                tools: ["kicad_route_pass"],
                versionOutput: "KiCad Version: 9.0.0"
            ),
            client: client,
            requiredMajorVersion: 10
        )

        let result = try await executor.execute(toolName: "kicad_route_pass", arguments: [:])

        XCTAssertEqual(result.status, .blockedVersion)
        XCTAssertEqual(client.calls.count, 0)
    }

    func test_successPathDoesNotSynthesizeBoundaryStubArtifact() async throws {
        let expected = KiCadToolResult(
            status: .complete,
            artifacts: [ArtifactRef(path: "/tmp/kicad/export.zip", kind: "archive")]
        )
        let client = FakeKiCadMCPClient(responseJSON: Self.makeResultJSON(expected))
        let executor = KiCadMCPToolExecutor(
            config: Self.makeConfig(),
            probe: .available(tools: ["kicad_export_fab"]),
            client: client
        )

        let result = try await executor.execute(toolName: "kicad_export_fab", arguments: [:])

        XCTAssertEqual(result.artifacts, expected.artifacts)
        XCTAssertFalse(result.artifacts.contains(where: { $0.kind == "kicad_boundary_stub" }))
    }

    func test_malformedPayloadReturnsBlockedToolingWithWarning() async throws {
        let client = FakeKiCadMCPClient(responseJSON: "{not-json")
        let executor = KiCadMCPToolExecutor(
            config: Self.makeConfig(),
            probe: .available(tools: ["kicad_export_fab"]),
            client: client
        )

        let result = try await executor.execute(toolName: "kicad_export_fab", arguments: [:])

        XCTAssertEqual(result.status, .blockedTooling)
        XCTAssertTrue(result.warnings.contains(where: { $0.code == "KICAD_MCP_RESULT_DECODE_FAILED" }))
    }

    private static func makeConfig(requiredToolNames: [String] = ["kicad_export_fab"]) -> KiCadMCPServerConfig {
        KiCadMCPServerConfig(
            serverPath: "/tmp/kicad-mcp-server",
            kicadCLIPath: "/usr/local/bin/kicad-cli",
            freeRoutingPath: "/usr/local/bin/freerouting",
            requiredToolNames: requiredToolNames
        )
    }

    private static func makeResultJSON(_ result: KiCadToolResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func canonicalJSONString(from arguments: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
private final class FakeKiCadMCPClient: KiCadMCPClient {
    struct Call {
        var toolName: String
        var arguments: [String: Any]
    }

    var calls: [Call] = []
    var responseJSON: String

    init(responseJSON: String) {
        self.responseJSON = responseJSON
    }

    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        calls.append(Call(toolName: toolName, arguments: arguments))
        return responseJSON
    }
}
