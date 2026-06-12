import XCTest
@testable import Merlin

@MainActor
final class ElectronicsToolingHealthTests: XCTestCase {
    func testMissingLocalFreeRoutingBlocksRoutePass() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .missingLocalFreeRouting).register(into: runtime)

        let response = await sendElectronics(runtime, capability: "kicad_route_pass", payload: "{}")
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.missingFreeRouting.rawValue)
    }

    func testUnsupportedKiCadVersionBlocksTooling() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .unsupportedVersion).register(into: runtime)

        let response = await sendElectronics(runtime, capability: "kicad_run_drc", payload: "{}")
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.unsupportedVersion.rawValue)
    }

    func testKiCadVersionCheckFallsBackFromBadPathToInstalledCLI() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli") else {
            throw XCTSkip("KiCad CLI is not installed in the standard macOS app bundle path")
        }
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let response = await sendElectronics(
            runtime,
            capability: "kicad_check_version",
            payload: #"{"kicad_cli_path":"/usr/local/bin/kicad-cli","required_major":10}"#
        )
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(result.status, .complete)
        XCTAssertTrue(result.warnings.contains { $0.code == "KICAD_CONFIGURED_PATH_UNUSABLE" })
    }

    func testMissingProjectFileBlocksProjectTools() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let response = await sendElectronics(runtime, capability: "kicad_run_drc", payload: #"{"project_path":"/tmp/not-real.kicad_pro"}"#)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.missingProjectFile.rawValue)
    }
}
