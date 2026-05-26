import XCTest
@testable import Merlin

@MainActor
final class ElectronicsRealRegistrationTests: XCTestCase {
    func testAllRequiredElectronicsCapabilitiesUsePluginNamespace() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let capabilities = await runtime.bus.registeredCapabilities()
        let names = Set(capabilities.map(\.address.capability))
        for tool in KiCadToolDefinitions.requiredToolNames {
            XCTAssertTrue(names.contains(tool), tool)
        }
        XCTAssertTrue(names.contains("workflow.schematic_to_pcb"))
        XCTAssertTrue(names.contains("workflow.requirements_to_pcb"))
        XCTAssertTrue(capabilities.allSatisfy { $0.address.namespace == "plugin.electronics" })
    }

    func testNonRouteElectronicsToolDoesNotReturnGenericOkPlaceholder() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let response = await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_run_drc"),
            origin: .parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString("{}"),
            cancellationGroup: nil
        ))
        XCTAssertNotEqual(response.status, .ok)
        XCTAssertFalse(response.payload?.stringValue().contains(#""status":"COMPLETE""#) ?? false)
    }
}

