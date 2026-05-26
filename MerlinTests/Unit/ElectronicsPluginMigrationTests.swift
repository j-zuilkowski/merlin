import XCTest
@testable import Merlin

@MainActor
final class ElectronicsPluginMigrationTests: XCTestCase {
    func testElectronicsPluginMetadataIsCanonical() throws {
        let plugin = ElectronicsRuntimePlugin()
        XCTAssertEqual(plugin.metadata.id, "electronics")
        XCTAssertEqual(plugin.metadata.trustTier, .tier1)
        XCTAssertTrue(plugin.metadata.domainIDs.contains(ElectronicsDomain.defaultID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoPath("plugins/electronics/plugin.json")))
    }

    func testElectronicsPluginRegistersKiCadBusCapabilities() async throws {
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-electronics-plugin-tests-\(UUID().uuidString)")
        )
        let plugin = ElectronicsRuntimePlugin()
        try await plugin.register(into: runtime)

        for tool in ["kicad_check_version", "kicad_route_pass", "kicad_run_drc", "kicad_export_fab"] {
            let route = WorkspaceMessageAddress(namespace: "plugin.electronics", capability: tool)
            let hasRoute = await runtime.bus.hasRoute(route)
            XCTAssertTrue(hasRoute, tool)
        }
        let order = plugin.metadata.capabilities.first { $0.address.capability == "kicad_submit_vendor_order" }
        XCTAssertEqual(order?.requiredPermissionScope, .userApprovedIrreversible)
    }

    func testElectronicsPluginPublishesSharedProgressAndArtifactEvents() async throws {
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-electronics-plugin-tests-\(UUID().uuidString)")
        )
        let plugin = ElectronicsRuntimePlugin(routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(
            status: .complete,
            artifacts: [ArtifactRef(path: "/tmp/route.ses", kind: ElectronicsArtifactKind.routingResult.rawValue)]
        )))
        try await plugin.register(into: runtime)
        let payload = """
        {
          "job_id": "migration-route",
          "board_path": "/tmp/board.kicad_pcb",
          "dsn_path": "/tmp/route.dsn",
          "ses_path": "/tmp/route.ses",
          "log_path": "/tmp/route.log",
          "max_iterations": 3
        }
        """
        let response = await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_route_pass"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))

        XCTAssertEqual(response.status, .ok)
        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
        XCTAssertTrue(events.contains { $0.kind == .progress })
        XCTAssertTrue(events.contains { $0.kind == .artifactProduced })
    }

    private func repoPath(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
            .path
    }
}
