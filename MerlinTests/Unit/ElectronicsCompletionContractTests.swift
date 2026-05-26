import XCTest
@testable import Merlin

@MainActor
final class ElectronicsCompletionContractTests: XCTestCase {
    func testCompletionContractDeclaresWorkflowFirstScope() {
        let contract = ElectronicsCompletionContract.current

        XCTAssertEqual(contract.requiredWorkflows, [.requirementsToPCB, .schematicToPCB])
        XCTAssertTrue(contract.requiredArtifactKinds.contains(.kicadProject))
        XCTAssertTrue(contract.requiredArtifactKinds.contains(.routingResult))
        XCTAssertTrue(contract.requiredArtifactKinds.contains(.fabricationPackage))
        XCTAssertTrue(contract.requiredArtifactKinds.contains(.bom))
        XCTAssertTrue(contract.requiredArtifactKinds.contains(.verificationReport))
        XCTAssertTrue(contract.requiredGates.contains(.erc))
        XCTAssertTrue(contract.requiredGates.contains(.drc))
        XCTAssertTrue(contract.requiredGates.contains(.parity))
        XCTAssertTrue(contract.requiredGates.contains(.fabrication))
        XCTAssertTrue(contract.requiredGates.contains(.connectivity))
        XCTAssertEqual(contract.requiredRoutingBackend, .localFreeRouting)
        XCTAssertEqual(contract.hostedRoutingPolicy, .optionalConfigured)
    }

    func testElectronicsPluginRegistersCompletionWorkflowRoutes() async throws {
        let runtime = try makeRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        for capability in ["workflow.requirements_to_pcb", "workflow.schematic_to_pcb"] {
            let hasRoute = await runtime.bus.hasRoute(WorkspaceMessageAddress(namespace: "plugin.electronics", capability: capability))
            XCTAssertTrue(hasRoute, capability)
        }
    }

    func testMissingToolingReturnsBlockedEventInsteadOfPlaceholderComplete() async throws {
        let runtime = try makeRuntime()
        try await ElectronicsRuntimePlugin(tooling: .missingKiCad).register(into: runtime)

        let requestID = UUID()
        let response = await runtime.bus.send(WorkspaceMessageRequest(
            id: requestID,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_route_pass"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString("{}"),
            cancellationGroup: nil
        ))

        XCTAssertEqual(response.status, .blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.missingKiCad.rawValue)

        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
        XCTAssertTrue(events.contains { $0.requestID == requestID && $0.kind == .diagnostic })
    }

    func testProductionCodeDoesNotRouteThroughArchivedMCPScaffold() throws {
        let root = repoRoot()
        let productionFiles = try FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("Merlin").path)
            .filter { $0.hasSuffix(".swift") }

        for relativePath in productionFiles {
            let text = try String(contentsOf: root.appendingPathComponent("Merlin").appendingPathComponent(relativePath), encoding: .utf8)
            XCTAssertFalse(text.contains("archive/legacy-merlin-kicad-mcp"), relativePath)
            XCTAssertFalse(text.contains("plugins/merlin-kicad-mcp"), relativePath)
        }
    }

    private func makeRuntime() throws -> WorkspaceRuntime {
        try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-electronics-completion-\(UUID().uuidString)")
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
