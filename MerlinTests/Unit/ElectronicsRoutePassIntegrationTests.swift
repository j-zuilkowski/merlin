import XCTest
@testable import Merlin

@MainActor
final class ElectronicsRoutePassIntegrationTests: XCTestCase {
    func testRoutePassInvokesInjectedLocalFreeRoutingBackend() async throws {
        let backend = RecordingElectronicsRouteBackend(result: KiCadToolResult(
            status: .complete,
            artifacts: [ArtifactRef(path: "/tmp/out.ses", kind: ElectronicsArtifactKind.routingResult.rawValue)]
        ))
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(routeBackend: backend).register(into: runtime)

        let payload = """
        {
          "job_id": "job-1",
          "board_path": "/tmp/board.kicad_pcb",
          "dsn_path": "/tmp/in.dsn",
          "ses_path": "/tmp/out.ses",
          "log_path": "/tmp/route.log",
          "max_iterations": 3
        }
        """
        let response = await sendElectronics(runtime, capability: "kicad_route_pass", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.ok)
        let callCount = await backend.recordedCallCount()
        XCTAssertEqual(callCount, 1)
        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
        XCTAssertTrue(events.contains { $0.kind == .artifactProduced })
    }

    func testRoutePassBlocksWhenBackendFails() async throws {
        let backend = RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .blocked))
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(routeBackend: backend).register(into: runtime)

        let payload = """
        {
          "job_id": "job-2",
          "board_path": "/tmp/board.kicad_pcb",
          "dsn_path": "/tmp/in.dsn",
          "ses_path": "/tmp/out.ses",
          "log_path": "/tmp/route.log",
          "max_iterations": 3
        }
        """
        let response = await sendElectronics(runtime, capability: "kicad_route_pass", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
    }
}
