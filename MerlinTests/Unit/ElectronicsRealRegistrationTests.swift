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

    func testSchematicIngestEmitsCompanionOCRExtractionReport() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let fixtureDirectory = temporaryDirectory("schematic-ocr-fixture")
        let imageURL = fixtureDirectory.appendingPathComponent("rc-filter.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        try """
        {
          "schematic": "RC low-pass filter",
          "components": [
            { "designator": "R1", "value": "10k", "type": "resistor" },
            { "designator": "C1", "value": "100nF", "type": "capacitor" }
          ],
          "nets": [
            { "name": "VIN", "pins": ["R1-1"] },
            { "name": "OUT", "pins": ["R1-2", "C1-1"] },
            { "name": "GND", "pins": ["C1-2"] }
          ]
        }
        """.write(
            to: fixtureDirectory.appendingPathComponent("ground-truth.json"),
            atomically: true,
            encoding: .utf8
        )

        let response = await sendElectronics(
            runtime,
            capability: "kicad_ingest_schematic",
            payload: #"{"design_id":"rc-filter","source_artifact_path":"\#(imageURL.path)","source_type":"raster_image","dpi":300}"#
        )

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.nextActions.contains { $0.contains("R1=10k") && $0.contains("C1=100nF") })
        let artifact = try XCTUnwrap(result.artifacts.first { $0.kind == "extraction_report" })
        let report = try JSONDecoder().decode(ExtractionReport.self, from: Data(contentsOf: URL(fileURLWithPath: artifact.path)))
        XCTAssertEqual(report.extractedComponents.map(\.refdes), ["R1", "C1"])
        XCTAssertEqual(report.extractedComponents.map(\.value), ["10k", "100nF"])
        XCTAssertEqual(report.extractedNets.map(\.name), ["VIN", "OUT", "GND"])
    }

    func testElectronicsPluginCapabilitiesAreOfferedAsAgentTools() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(
            tooling: .available,
            routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))
        ).register(into: runtime)

        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let router = ToolRouter(
            authGate: AuthGate(memory: memory, presenter: AllowingAuthPresenter()),
            workspaceRuntime: runtime,
            originProvider: { route in
                WorkspaceMessageOrigin.parentSession(
                    workspaceID: runtime.workspaceID,
                    sessionID: nil,
                    activeDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID],
                    permissionScope: route.requiredPermissionScope
                )
            }
        )
        router.registerWorkspaceCapabilityTools(await runtime.bus.registeredCapabilities())

        let offered = Set(router.workspaceToolDefinitions(
            activeDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        ).map(\.function.name))
        XCTAssertTrue(offered.contains("kicad_route_pass"))

        let result = await router.dispatch([
            ToolCall(
                id: "call-1",
                type: "function",
                function: FunctionCall(
                    name: "kicad_route_pass",
                    arguments: #"{"job_id":"fixture","board_path":"/tmp/project.kicad_pcb","dsn_path":"/tmp/project.dsn","ses_path":"/tmp/project.ses","log_path":"/tmp/project-route.log","max_iterations":3}"#
                )
            )
        ], permissionModeOverride: .autoAccept).first
        XCTAssertFalse(result?.isError ?? true)
        XCTAssertFalse(result?.content.contains("ROUTE_NOT_FOUND") ?? true)
    }
}

private final class AllowingAuthPresenter: AuthPresenter {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        .allow
    }
}
