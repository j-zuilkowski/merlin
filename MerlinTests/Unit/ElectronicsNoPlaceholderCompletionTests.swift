import XCTest
@testable import Merlin

@MainActor
final class ElectronicsNoPlaceholderCompletionTests: XCTestCase {
    func testWorkflowRoutesBlockEmptyPayloadsInsteadOfCompleting() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        for capability in ["workflow.schematic_to_pcb", "workflow.requirements_to_pcb"] {
            let response = await runtime.bus.send(WorkspaceMessageRequest(
                id: UUID(),
                address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: capability),
                origin: .parentSession(
                    workspaceID: runtime.workspaceID,
                    sessionID: nil,
                    activeDomainIDs: [ElectronicsDomain.defaultID],
                    permissionScope: .externalSideEffect
                ),
                payload: .jsonString("{}"),
                cancellationGroup: nil
            ))
            XCTAssertNotEqual(response.status, WorkspaceMessageResponseStatus.ok, capability)
            XCTAssertFalse(response.payload?.stringValue().contains(#""status":"COMPLETE""#) ?? false, capability)
        }
    }

    func testElectronicsRuntimePluginSourceHasNoHardCodedCompletePlaceholders() throws {
        let source = try repoText("Merlin/Plugins/ElectronicsRuntimePlugin.swift")
        XCTAssertFalse(source.contains(#""{\"status\":\"COMPLETE\"}""#))
        XCTAssertFalse(source.contains(#"{"status":"COMPLETE"}"#))
        XCTAssertFalse(source.contains("U1 NE555"))
        XCTAssertFalse(source.contains("R1=10k"))
        XCTAssertFalse(source.contains("C1=10uF"))
    }
}
