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

    func testMissingProjectFileBlocksProjectTools() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let response = await sendElectronics(runtime, capability: "kicad_run_drc", payload: #"{"project_path":"/tmp/not-real.kicad_pro"}"#)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.missingProjectFile.rawValue)
    }
}
