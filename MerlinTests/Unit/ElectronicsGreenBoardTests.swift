import XCTest
@testable import Merlin

@MainActor
final class ElectronicsGreenBoardTests: XCTestCase {
    func testNoCurrentSpecOrVisionWordingNamesLegacyMCPAsActive() throws {
        let docs = try ["spec.md", "vision.md", "FEATURES.md", "Merlin/Docs/UserGuide.md", "Merlin/Docs/DeveloperManual.md"]
            .map { try repoText($0) }
            .joined(separator: "\n")

        XCTAssertFalse(docs.contains("`merlin-kicad-mcp`, raster/PDF schematic ingestion"))
        XCTAssertFalse(docs.contains("`merlin-kicad-mcp` 22-tool contract"))
        XCTAssertFalse(docs.contains("Missing `merlin-kicad-mcp` or missing required tool"))
    }

    func testElectronicsManifestUsesFirstPartyDynamicLibraryMetadata() throws {
        let data = try Data(contentsOf: repoURL("plugins/electronics/plugin.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["built_in_factory"])
        XCTAssertEqual(object["dynamic_library_path"] as? String, "plugins/electronics/libMerlinElectronicsPlugin.dylib")
        XCTAssertEqual(object["bootstrap_symbol"] as? String, "merlin_electronics_plugin_bootstrap_json")
        XCTAssertEqual(object["handler_symbol"] as? String, "merlin_electronics_plugin_handle_json")
        let capabilities = try XCTUnwrap(object["capabilities"] as? [[String: Any]])
        let manifestTools = Set(capabilities.compactMap { ($0["address"] as? [String: Any])?["capability"] as? String })
        XCTAssertTrue(Set(KiCadToolDefinitions.requiredToolNames).isSubset(of: manifestTools))
    }

    func testEveryKiCadCapabilityHasDomainHandlerResult() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)

        for tool in KiCadToolDefinitions.requiredToolNames {
            let payload = fixturePayload(for: tool)
            let response = await sendElectronics(
                runtime,
                capability: tool,
                payload: payload,
                scope: tool == "kicad_submit_vendor_order" ? .userApprovedIrreversible : .externalSideEffect
            )
            XCTAssertNotEqual(response.diagnostics.first?.code, "ROUTE_NOT_FOUND", tool)
            XCTAssertFalse(response.payload?.stringValue() == #"{"status":"COMPLETE"}"#, tool)
            XCTAssertTrue([.ok, .blocked].contains(response.status), tool)
            XCTAssertNoThrow(try response.payload?.decodeJSON(KiCadToolResult.self), tool)
        }
    }

    func testFixtureWorkflowProducesCompleteEvidenceWithoutExternalTooling() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)

        let payload = try workflowPayload(jobID: "green-board", highStakes: false)
        let response = await sendElectronics(runtime, capability: "workflow.schematic_to_pcb", payload: payload)
        XCTAssertEqual(response.status, .ok)
        let report = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsFinalReport.self))
        XCTAssertEqual(report.status, .complete)
    }

    private func fixturePayload(for tool: String) -> String {
        switch tool {
        case "kicad_check_version":
            return #"{"kicad_cli_path":"/usr/bin/false","required_major":10}"#
        case "kicad_ingest_schematic":
            return #"{"design_id":"fixture","source_artifact_path":"/tmp/source.kicad_sch","source_type":"native_kicad","extraction_profile":"default","dpi":300}"#
        case "kicad_answer_clarification":
            return #"{"design_id":"fixture","answers_json":"{}"}"#
        case "kicad_build_intent_model":
            return #"{"design_id":"fixture","input_artifact_path":"/tmp/extraction.json","board_profile_id":"jlcpcb_2layer_default"}"#
        case "kicad_select_components", "kicad_prepare_libraries", "kicad_assign_footprints",
             "kicad_apply_board_profile", "kicad_generate_net_classes", "kicad_place_components",
             "kicad_check_connectivity", "kicad_run_erc", "kicad_run_drc", "kicad_check_parity",
             "kicad_run_spice", "kicad_evaluate_simulation", "kicad_visual_inspect":
            return #"{"design_id":"fixture","project_path":"/tmp/project.kicad_pro"}"#
        case "kicad_compile_project":
            return #"{"design_id":"fixture","design_intent_path":"/tmp/design.json","output_directory":"/tmp/merlin-electronics-fixture"}"#
        case "kicad_route_pass":
            return #"{"job_id":"fixture","board_path":"/tmp/project.kicad_pcb","dsn_path":"/tmp/project.dsn","ses_path":"/tmp/project.ses","log_path":"/tmp/project-route.log","max_iterations":3}"#
        case "kicad_export_fab":
            return #"{"design_id":"fixture","project_path":"/tmp/project.kicad_pro","fabricator_profile_id":"jlcpcb_2layer_default","output_directory":"/tmp/merlin-electronics-fab"}"#
        case "kicad_prepare_vendor_order":
            return #"{"design_id":"fixture","normalized_bom_path":"/tmp/bom.json","vendor_id":"Digi-Key","quantity":1}"#
        case "kicad_submit_vendor_order":
            return #"{"job_id":"fixture","approved":false}"#
        case "kicad_package_release":
            return #"{"job_id":"fixture","approved":false}"#
        default:
            return #"{"design_id":"fixture"}"#
        }
    }
}
