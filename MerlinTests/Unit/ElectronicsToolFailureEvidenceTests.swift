import XCTest
@testable import Merlin

@MainActor
final class ElectronicsToolFailureEvidenceTests: XCTestCase {
    func testFailedDRCRunKeepsReportArtifactForHarnessRepairEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let project = try writeKiCadProjectFixture()
        let tool = try writeFailingKiCadCLI()

        let response = await sendElectronics(
            runtime,
            capability: "kicad_run_drc",
            payload: #"{"project_path":"\#(project.path)","kicad_cli_path":"\#(tool.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let toolResult = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertNotEqual(toolResult.status, .complete)
        let drcPath = try XCTUnwrap(toolResult.artifacts.first { $0.kind == "drc_report" }?.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: drcPath))
        XCTAssertEqual(toolResult.handoff?.drcReportPath, drcPath)

        let evidencePaths = try writeHarnessArtifactPaths(drcReportPath: drcPath)
        let evidence = try ElectronicsEvidenceArtifactAdapter().buildEvidence(evidencePaths)
        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: loadFixture("amp_low_voltage_audio/design_intent.json"),
            circuitIR: loadFixture("amp_low_voltage_audio/circuit_ir.json"),
            outputDirectory: temporaryDirectory("failed-drc-harness-output"),
            evidence: evidence
        ))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.pcbStatus, .blocked)
        XCTAssertTrue(result.missingEvidence.contains("PCB_VERIFIED"))
        XCTAssertTrue(result.diagnostics.contains { $0.code == "BLOCKING_DRC_VIOLATION" }, "\(result)")
    }

    func testFailedSPICERunKeepsMeasurementArtifactForRepairEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let project = try writeKiCadProjectFixture()
        let deck = try writeFixtureFile(
            name: "fixture.cir",
            text: """
            * failing spice fixture
            V1 in 0 DC 1
            R1 in 0 1k
            .op
            .end
            """
        )
        let ngspice = try writeFailingNgspice()

        let response = await sendElectronics(
            runtime,
            capability: "kicad_run_spice",
            payload: #"{"project_path":"\#(project.path)","scenario_path":"\#(deck.path)","ngspice_path":"\#(ngspice.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let toolResult = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertNotEqual(toolResult.status, .complete)
        let spicePath = try XCTUnwrap(toolResult.artifacts.first { $0.kind == "spice_measurements" }?.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: spicePath))
        XCTAssertEqual(toolResult.handoff?.spiceMeasurementsPath, spicePath)
        let log = try String(contentsOfFile: spicePath, encoding: .utf8)
        XCTAssertTrue(log.contains("fatal ngspice fixture error"))
    }

    func testERCRepairActionPlansSupportedDiagnosticsAndPreservesPatchArtifact() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("erc-repair-runtime")
        let ercReport = try writeFixtureFile(
            name: "erc-report.json",
            text: #"{"violations":[{"id":"erc-1","code":"power_pin_not_driven","severity":"error","message":"Power input not driven","refs":["+VRAW"]}]}"#,
            in: root
        )
        let circuitIR = repoURL("plugins/electronics/fixtures/amp_low_voltage_audio/circuit_ir.json")

        let response = await sendElectronics(
            runtime,
            capability: "kicad_repair_erc_from_diagnostics",
            payload: #"{"erc_report_path":"\#(ercReport.path)","circuit_ir_path":"\#(circuitIR.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        let planPath = try XCTUnwrap(result.artifacts.first { $0.kind == "erc_repair_plan" }?.path)
        let plan = try JSONDecoder().decode(ERCRepairPlan.self, from: Data(contentsOf: URL(fileURLWithPath: planPath)))
        XCTAssertEqual(plan.patches.map(\.action), ["add_or_correct_power_flag"])
        XCTAssertTrue(result.nextActions.contains("kicad_apply_erc_repair_patch"))
        XCTAssertTrue(result.nextActions.contains("kicad_run_erc"))
    }

    func testERCRepairPatchApplicationRecordsUnverifiedRerunRequirement() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("erc-repair-application")
        let circuitIR: CircuitIR = try loadFixture("amp_low_voltage_audio/circuit_ir.json")
        let materialized = try CircuitIRKiCadSchematicMaterializer().materialize(
            circuitIR: circuitIR,
            outputDirectory: root
        )
        let plan = ERCRepairPlan(
            patches: [
                ERCRepairPatch(
                    violationId: "erc-nc-1",
                    repairClass: .explicitNoConnect,
                    targetRef: "Symbol QOUT1 Pin 2 [C, Passive, Line]",
                    action: "add_no_connect",
                    details: "unused output transistor pin requires explicit no-connect"
                ),
            ],
            unsupportedViolations: []
        )
        let planPath = root.appendingPathComponent("erc-repair-plan.json")
        try JSONEncoder().encode(plan).write(to: planPath)

        let response = await sendElectronics(
            runtime,
            capability: "kicad_apply_erc_repair_patch",
            payload: #"{"erc_repair_plan_path":"\#(planPath.path)","schematic_path":"\#(materialized.schematicURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        let applicationPath = try XCTUnwrap(result.artifacts.first { $0.kind == "erc_repair_application" }?.path)
        let application = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: applicationPath))
        ) as? [String: Any])
        XCTAssertEqual(application["status"] as? String, "patch_applied_requires_rerun")
        XCTAssertEqual(application["requires_rerun_tool"] as? String, "kicad_run_erc")
        XCTAssertEqual(application["verified"] as? Bool, false)
        XCTAssertNil(result.handoff?.ercReportPath)
        XCTAssertTrue(result.nextActions.contains("kicad_run_erc"))
    }

    func testDRCRepairActionPlansSupportedDiagnosticsAndBlocksApprovalRequiredDiagnostics() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("drc-repair-runtime")
        let clearanceReport = try writeFixtureFile(
            name: "clearance-report.json",
            text: #"{"violations":[{"id":"drc-1","code":"clearance","severity":"error","message":"Track clearance is below rule.","refs":["R1","C1"]}]}"#,
            in: root
        )

        let planned = await sendElectronics(
            runtime,
            capability: "kicad_repair_drc_from_diagnostics",
            payload: #"{"drc_report_path":"\#(clearanceReport.path)"}"#
        )

        XCTAssertEqual(planned.status, .ok)
        let plannedResult = try XCTUnwrap(planned.payload?.decodeJSON(KiCadToolResult.self))
        let planPath = try XCTUnwrap(plannedResult.artifacts.first { $0.kind == "drc_repair_plan" }?.path)
        let planBody = try String(contentsOfFile: planPath, encoding: .utf8)
        XCTAssertTrue(planBody.contains("adjust_clearance_rule"), planBody)
        XCTAssertTrue(plannedResult.nextActions.contains("kicad_apply_drc_repair_patch"))
        XCTAssertTrue(plannedResult.nextActions.contains("kicad_run_drc"))

        let approvalReport = try writeFixtureFile(
            name: "approval-report.json",
            text: #"{"violations":[{"id":"drc-2","code":"layer_count_change_required","severity":"error","message":"Needs more layers.","refs":["board"]}]}"#,
            in: root
        )
        let blocked = await sendElectronics(
            runtime,
            capability: "kicad_repair_drc_from_diagnostics",
            payload: #"{"drc_report_path":"\#(approvalReport.path)"}"#
        )

        XCTAssertEqual(blocked.status, .blocked)
        let blockedResult = try XCTUnwrap(blocked.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(blockedResult.warnings.contains { $0.code == "DRC_REPAIR_REQUIRES_APPROVAL" })
    }

    func testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("drc-repair-application")
        let project = try writeRoutableKiCadProjectFixture()
        let board = project.deletingPathExtension().appendingPathExtension("kicad_pcb")
        let originalBoard = try String(contentsOf: board, encoding: .utf8)
        let drcPlan = try writeFixtureFile(
            name: "drc-plan.json",
            text: """
            {
              "status": "repair_planned",
              "patches": [
                {
                  "violationId": "drc-place",
                  "repairClass": "placement",
                  "targetRefs": ["R1", "C1"],
                  "action": "adjust_placement"
                },
                {
                  "violationId": "drc-clearance",
                  "repairClass": "clearance",
                  "targetRefs": ["Net-(R1-Pad1)"],
                  "action": "adjust_clearance_rule"
                },
                {
                  "violationId": "drc-net-class",
                  "repairClass": "net_class",
                  "targetRefs": ["Net-(R1-Pad1)"],
                  "action": "adjust_net_class"
                },
                {
                  "violationId": "drc-route",
                  "repairClass": "routing",
                  "targetRefs": ["Net-(R1-Pad1)"],
                  "action": "reroute_or_report_unrouted"
                }
              ],
              "diagnostics": []
            }
            """,
            in: root
        )

        let response = await sendElectronics(
            runtime,
            capability: "kicad_apply_drc_repair_patch",
            payload: #"{"drc_repair_plan_path":"\#(drcPlan.path)","project_path":"\#(project.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        let applicationPath = try XCTUnwrap(result.artifacts.first { $0.kind == "drc_repair_application" }?.path)
        let mutationPath = try XCTUnwrap(result.artifacts.first { $0.kind == "layout_mutation_evidence" }?.path)
        let application = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: applicationPath))
        ) as? [String: Any])
        let mutation = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: mutationPath))
        ) as? [String: Any])
        let updatedBoard = try String(contentsOf: board, encoding: .utf8)

        XCTAssertNotEqual(updatedBoard, originalBoard)
        XCTAssertTrue(updatedBoard.contains(#"(at 17 "#), updatedBoard)
        XCTAssertTrue(updatedBoard.contains(#"(clearance 0.2)"#), updatedBoard)
        XCTAssertTrue(updatedBoard.contains(#"(trace_width 0.3)"#), updatedBoard)
        XCTAssertTrue(updatedBoard.contains(#"(segment "#), updatedBoard)
        XCTAssertTrue(updatedBoard.contains(#"(via "#), updatedBoard)
        XCTAssertFalse(updatedBoard.contains("Merlin reroute required"), updatedBoard)
        XCTAssertEqual(application["status"] as? String, "patch_applied_requires_drc_rerun")
        XCTAssertEqual(application["verified"] as? Bool, false)
        XCTAssertEqual(application["requires_rerun_tool"] as? String, "kicad_run_drc")
        XCTAssertEqual(application["requires_layout_mutation"] as? Bool, false)
        XCTAssertEqual(application["layout_mutation_evidence_path"] as? String, mutationPath)
        XCTAssertEqual(mutation["status"] as? String, "layout_mutated_requires_drc_rerun")
        XCTAssertEqual(mutation["board_path"] as? String, board.path)
        XCTAssertNotEqual(mutation["before_hash"] as? String, mutation["after_hash"] as? String)
        XCTAssertEqual(mutation["verified"] as? Bool, false)
        XCTAssertEqual(mutation["requires_rerun_tool"] as? String, "kicad_run_drc")
        XCTAssertEqual(mutation["patch_ids"] as? [String], ["drc-place", "drc-clearance", "drc-net-class", "drc-route"])
        let changedObjects = try XCTUnwrap(mutation["changed_objects"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(changedObjects.count, 4)
        XCTAssertTrue(changedObjects.contains { $0["kind"] as? String == "routing_segment" }, "\(changedObjects)")
        XCTAssertTrue(changedObjects.contains { $0["kind"] as? String == "routing_via" }, "\(changedObjects)")
        XCTAssertFalse(changedObjects.contains { $0["kind"] as? String == "routing_marker" }, "\(changedObjects)")
        XCTAssertNil(result.handoff?.drcReportPath)
        XCTAssertEqual(result.nextActions, ["kicad_run_drc"])
    }

    func testDRCRepairPatchApplicationBlocksRoutingWithoutPadGeometry() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("drc-routing-repair-no-geometry")
        let project = try writeMutableKiCadProjectFixture()
        let board = project.deletingPathExtension().appendingPathExtension("kicad_pcb")
        let originalBoard = try String(contentsOf: board, encoding: .utf8)
        let drcPlan = try writeFixtureFile(
            name: "drc-plan.json",
            text: """
            {
              "status": "repair_planned",
              "patches": [
                {
                  "violationId": "drc-route",
                  "repairClass": "routing",
                  "targetRefs": ["Net-(R1-Pad1)"],
                  "action": "reroute_or_report_unrouted"
                }
              ],
              "diagnostics": []
            }
            """,
            in: root
        )

        let response = await sendElectronics(
            runtime,
            capability: "kicad_apply_drc_repair_patch",
            payload: #"{"drc_repair_plan_path":"\#(drcPlan.path)","project_path":"\#(project.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertNotEqual(result.status, .complete)
        XCTAssertEqual(result.nextActions, ["regenerate_drc_repair_plan"])
        XCTAssertTrue(result.warnings.contains { $0.message.contains("concrete PCB/layout changes") }, "\(result.warnings)")
        let updatedBoard = try String(contentsOf: board, encoding: .utf8)
        XCTAssertEqual(updatedBoard, originalBoard)
        XCTAssertFalse(updatedBoard.contains("Merlin reroute required"), updatedBoard)
    }

    func testSPICERepairActionPlansMeasurementRepairAndBlocksUnsupportedLog() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("spice-repair-runtime")
        let measurements = try writeFixtureFile(name: "ngspice.log", text: "output_power_w = 18.0\n", in: root)
        let scenario = try writeFixtureFile(
            name: "scenario.json",
            text: """
            {
              "scenario_id": "amp-output-stage",
              "design_id": "amp",
              "circuit_path": "\(root.appendingPathComponent("amp.cir").path)",
              "analyses": ["tran"],
              "required_model_refs": ["MJ15003G"],
              "measurement_envelopes": [
                { "name": "output_power_w", "min": 24.0, "max": 28.0 }
              ]
            }
            """,
            in: root
        )

        let missingBounds = await sendElectronics(
            runtime,
            capability: "kicad_repair_spice_from_diagnostics",
            payload: #"{"spice_measurements_path":"\#(measurements.path)","scenario_path":"\#(scenario.path)"}"#
        )

        XCTAssertEqual(missingBounds.status, .blocked)
        let missingBoundsResult = try XCTUnwrap(missingBounds.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(missingBoundsResult.warnings.contains { $0.code == "SPICE_REPAIR_PARAMETER_BOUNDS_REQUIRED" })

        let response = await sendElectronics(
            runtime,
            capability: "kicad_repair_spice_from_diagnostics",
            payload: #"{"spice_measurements_path":"\#(measurements.path)","scenario_path":"\#(scenario.path)","repair_parameters":[{"name":"bias_current","value":2.8,"min":2.0,"max":3.5}]}"#
        )

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        let planPath = try XCTUnwrap(result.artifacts.first { $0.kind == "spice_repair_plan" }?.path)
        let plan = try JSONDecoder().decode(SPICESimulationRepairPlan.self, from: Data(contentsOf: URL(fileURLWithPath: planPath)))
        XCTAssertEqual(plan.patches.map(\.action), ["adjust_bias_current_within_declared_bounds"])
        XCTAssertTrue(result.nextActions.contains("kicad_apply_spice_repair_patch"))
        XCTAssertTrue(result.nextActions.contains("kicad_run_spice"))

        let unsupportedMeasurements = try writeFixtureFile(name: "unsupported.log", text: "slew_rate_v_us = 0.1\n", in: root)
        let unsupportedScenario = try writeFixtureFile(
            name: "unsupported-scenario.json",
            text: """
            {
              "scenario_id": "amp-slew",
              "design_id": "amp",
              "circuit_path": "\(root.appendingPathComponent("amp.cir").path)",
              "analyses": ["tran"],
              "required_model_refs": ["MJ15003G"],
              "measurement_envelopes": [
                { "name": "slew_rate_v_us", "min": 5.0 }
              ]
            }
            """,
            in: root
        )
        let blocked = await sendElectronics(
            runtime,
            capability: "kicad_repair_spice_from_diagnostics",
            payload: #"{"spice_measurements_path":"\#(unsupportedMeasurements.path)","scenario_path":"\#(unsupportedScenario.path)"}"#
        )

        XCTAssertEqual(blocked.status, .blocked)
        let blockedResult = try XCTUnwrap(blocked.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(blockedResult.warnings.contains { $0.code == "SPICE_REPAIR_UNSUPPORTED" })
    }

    func testVendorOrderPreparationRequiresRealBOMStockPriceAndDatasheetEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("vendor-order-missing-evidence")
        let bom = try writeFixtureFile(
            name: "bom.json",
            text: """
            {
              "design_id": "amp_low_voltage_audio",
              "lines": [
                {
                  "line_id": "line-1",
                  "mpn": "RC0603FR-0710KL",
                  "quantity": 2,
                  "reference_designators": ["R1", "R2"]
                }
              ],
              "vendor_mappings": [
                {
                  "vendor_id": "digikey",
                  "line_id": "line-1",
                  "vendor_part_number": "311-10.0KHRCT-ND"
                }
              ],
              "substitutions": []
            }
            """,
            in: root
        )

        let response = await sendElectronics(
            runtime,
            capability: "kicad_prepare_vendor_order",
            payload: #"{"normalized_bom_path":"\#(bom.path)","vendor_id":"Digi-Key","quantity":1}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(result.status, .blockedTooling)
        XCTAssertTrue(result.warnings.contains { $0.code == "BOM_VENDOR_EVIDENCE_REQUIRED" }, "\(result)")
        XCTAssertEqual(result.nextActions, ["attach_vendor_availability", "attach_datasheet_evidence"])
    }

    func testVendorOrderPreparationEmitsPackageFromValidatedBOMStockPriceAndCachedDatasheets() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("vendor-order-validated-evidence")
        let bom = try writeFixtureFile(
            name: "bom.json",
            text: """
            {
              "design_id": "amp_low_voltage_audio",
              "lines": [
                {
                  "line_id": "line-1",
                  "mpn": "RC0603FR-0710KL",
                  "quantity": 2,
                  "reference_designators": ["R1", "R2"]
                }
              ],
              "vendor_mappings": [
                {
                  "vendor_id": "digikey",
                  "line_id": "line-1",
                  "vendor_part_number": "311-10.0KHRCT-ND"
                }
              ],
              "substitutions": []
            }
            """,
            in: root
        )
        let availability = try writeFixtureFile(
            name: "availability.json",
            text: """
            [
              {
                "line_id": "line-1",
                "mpn": "RC0603FR-0710KL",
                "vendor_id": "digikey",
                "vendor_part_number": "311-10.0KHRCT-ND",
                "lifecycle": "active",
                "in_stock_quantity": 100,
                "unit_price_usd": 0.10,
                "source_url": "https://digikey.example/RC0603FR-0710KL"
              }
            ]
            """,
            in: root
        )
        let datasheetPDF = try writeFixtureFile(name: "rc0603.pdf", text: "%PDF-1.4\n", in: root)
        let datasheets = try writeFixtureFile(
            name: "datasheets.json",
            text: """
            [
              {
                "manufacturer": "Yageo",
                "mpn": "RC0603FR-0710KL",
                "url": "https://example.invalid/rc0603.pdf",
                "local_path": "\(datasheetPDF.path)",
                "sha256": "88f529ef82511e7d4cda07fd509e778ceef0a689da081729ffbd794a1d688cce",
                "provider_id": "digikey",
                "retrieved_at": "2026-06-07T00:00:00Z",
                "license": "cached-for-design-evidence",
                "citations": []
              }
            ]
            """,
            in: root
        )

        let response = await sendElectronics(
            runtime,
            capability: "kicad_prepare_vendor_order",
            payload: #"{"normalized_bom_path":"\#(bom.path)","vendor_availability_path":"\#(availability.path)","datasheet_evidence_path":"\#(datasheets.path)","vendor_id":"Digi-Key","quantity":1}"#
        )

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        let packagePath = try XCTUnwrap(result.artifacts.first { $0.kind == "vendor_order_package" }?.path)
        let package = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: packagePath))
        ) as? [String: Any])
        XCTAssertEqual(package["status"] as? String, "prepared")
        XCTAssertEqual(package["validated"] as? Bool, true)
        XCTAssertEqual(package["vendor_id"] as? String, "Digi-Key")
        XCTAssertEqual(package["normalized_bom_path"] as? String, bom.path)
        XCTAssertEqual(package["vendor_availability_path"] as? String, availability.path)
        XCTAssertEqual(package["datasheet_evidence_path"] as? String, datasheets.path)
        XCTAssertEqual(package["line_count"] as? Int, 1)
        XCTAssertEqual(try XCTUnwrap(package["total_estimate_usd"] as? Double), 0.2, accuracy: 0.0001)
        XCTAssertEqual(result.nextActions, ["review_vendor_order_package"])
    }

    func testRepairPatchApplicationRequiresGateRerunBeforeAdvancement() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let root = temporaryDirectory("repair-apply-runtime")
        let project = try writeMutableKiCadProjectFixture()
        let schematic = project.deletingPathExtension().appendingPathExtension("kicad_sch")

        let ercPlan = ERCRepairPlan(
            patches: [ERCRepairPatch(
                violationId: "erc-1",
                repairClass: .powerFlag,
                targetRef: "+VRAW",
                action: "add_or_correct_power_flag",
                details: "Power input not driven"
            )],
            unsupportedViolations: []
        )
        let ercPlanPath = root.appendingPathComponent("erc-plan.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(ercPlan).write(to: ercPlanPath)

        let ercApply = await sendElectronics(
            runtime,
            capability: "kicad_apply_erc_repair_patch",
            payload: #"{"erc_repair_plan_path":"\#(ercPlanPath.path)","schematic_path":"\#(schematic.path)"}"#
        )

        XCTAssertEqual(ercApply.status, .ok)
        let ercApplyResult = try XCTUnwrap(ercApply.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(ercApplyResult.artifacts.contains { $0.kind == "erc_repair_application" })
        XCTAssertFalse(ercApplyResult.artifacts.contains { $0.kind == "erc_report" })
        XCTAssertEqual(ercApplyResult.nextActions, ["kicad_run_erc"])
        XCTAssertNil(ercApplyResult.handoff?.ercReportPath)
        let updatedSchematic = try String(contentsOf: schematic, encoding: .utf8)
        XCTAssertFalse(updatedSchematic.contains("merlin_erc_repair"), updatedSchematic)
        XCTAssertNoThrow(try KiCadSchematicParser().parse(updatedSchematic))

        let drcPlan = try writeFixtureFile(
            name: "drc-plan.json",
            text: #"{"status":"repair_planned","patches":[{"violationId":"drc-1","repairClass":"clearance","targetRefs":["R1","C1"],"action":"adjust_clearance_rule"}],"diagnostics":[]}"#,
            in: root
        )
        let drcApply = await sendElectronics(
            runtime,
            capability: "kicad_apply_drc_repair_patch",
            payload: #"{"drc_repair_plan_path":"\#(drcPlan.path)","project_path":"\#(project.path)"}"#
        )

        XCTAssertEqual(drcApply.status, .ok)
        let drcApplyResult = try XCTUnwrap(drcApply.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(drcApplyResult.artifacts.contains { $0.kind == "drc_repair_application" })
        XCTAssertFalse(drcApplyResult.artifacts.contains { $0.kind == "drc_report" })
        XCTAssertEqual(drcApplyResult.nextActions, ["kicad_run_drc"])
        XCTAssertNil(drcApplyResult.handoff?.drcReportPath)
        XCTAssertTrue(drcApplyResult.artifacts.contains { $0.kind == "layout_mutation_evidence" })
        XCTAssertTrue(drcApplyResult.warnings.contains { $0.code == "DRC_PATCH_REQUIRES_RERUN" })

        let scenario = try writeFixtureFile(
            name: "scenario.json",
            text: """
            {
              "scenario_id": "amp-output-stage",
              "design_id": "amp",
              "circuit_path": "\(root.appendingPathComponent("amp.cir").path)",
              "analyses": ["tran"],
              "required_model_refs": ["MJ15003G"],
              "measurement_envelopes": [
                { "name": "output_power_w", "min": 24.0, "max": 28.0 }
              ]
            }
            """,
            in: root
        )
        let spicePlan = try writeFixtureFile(
            name: "spice-plan.json",
            text: #"{"patches":[{"repairClass":"parameter_adjustment","parameterName":"bias_current","action":"adjust_bias_current_within_declared_bounds"}],"requiresTopologyChange":false,"issues":[]}"#,
            in: root
        )
        let spiceApply = await sendElectronics(
            runtime,
            capability: "kicad_apply_spice_repair_patch",
            payload: #"{"spice_repair_plan_path":"\#(spicePlan.path)","scenario_path":"\#(scenario.path)"}"#
        )

        XCTAssertEqual(spiceApply.status, .ok)
        let spiceApplyResult = try XCTUnwrap(spiceApply.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(spiceApplyResult.artifacts.contains { $0.kind == "spice_repair_application" })
        XCTAssertFalse(spiceApplyResult.artifacts.contains { $0.kind == "spice_measurements" })
        XCTAssertEqual(spiceApplyResult.nextActions, ["kicad_run_spice"])
        XCTAssertNil(spiceApplyResult.handoff?.spiceMeasurementsPath)
        XCTAssertTrue(spiceApplyResult.warnings.contains { $0.code == "SPICE_PATCH_REQUIRES_DECK_MUTATOR" })
    }

    private func writeKiCadProjectFixture() throws -> URL {
        let directory = temporaryDirectory("tool-failure-kicad")
        let project = directory.appendingPathComponent("fixture.kicad_pro")
        let schematic = directory.appendingPathComponent("fixture.kicad_sch")
        let board = directory.appendingPathComponent("fixture.kicad_pcb")
        try #"{"meta":{"version":1}}"#.write(to: project, atomically: true, encoding: .utf8)
        try "(kicad_sch (version 20250114) (generator Merlin))\n".write(to: schematic, atomically: true, encoding: .utf8)
        try "(kicad_pcb (version 20250114) (generator Merlin))\n".write(to: board, atomically: true, encoding: .utf8)
        return project
    }

    private func writeMutableKiCadProjectFixture() throws -> URL {
        let directory = temporaryDirectory("tool-failure-mutable-kicad")
        let project = directory.appendingPathComponent("fixture.kicad_pro")
        let schematic = directory.appendingPathComponent("fixture.kicad_sch")
        let board = directory.appendingPathComponent("fixture.kicad_pcb")
        try #"{"meta":{"version":1}}"#.write(to: project, atomically: true, encoding: .utf8)
        try "(kicad_sch (version 20250114) (generator Merlin))\n".write(to: schematic, atomically: true, encoding: .utf8)
        try """
        (kicad_pcb
          (version 20250114)
          (generator "merlin-electronics")
          (setup
            (trace_clearance 0.15)
          )
          (net 1 "Net-(R1-Pad1)")
          (net_class Default "fixture"
            (clearance 0.15)
            (trace_width 0.25)
            (add_net "Net-(R1-Pad1)")
          )
          (footprint "Resistor_SMD:R_0805"
            (layer "F.Cu")
            (uuid "r1")
            (at 10 10 0)
            (property "Reference" "R1" (at 0 0 0) (layer "F.SilkS"))
          )
          (footprint "Capacitor_SMD:C_0805"
            (layer "F.Cu")
            (uuid "c1")
            (at 10 10 0)
            (property "Reference" "C1" (at 0 0 0) (layer "F.SilkS"))
          )
        )
        """.write(to: board, atomically: true, encoding: .utf8)
        return project
    }

    private func writeRoutableKiCadProjectFixture() throws -> URL {
        let project = try writeMutableKiCadProjectFixture()
        let board = project.deletingPathExtension().appendingPathExtension("kicad_pcb")
        try """
        (kicad_pcb
          (version 20250114)
          (generator "merlin-electronics")
          (setup
            (trace_clearance 0.15)
          )
          (net 1 "Net-(R1-Pad1)")
          (net_class Default "fixture"
            (clearance 0.15)
            (trace_width 0.25)
            (add_net "Net-(R1-Pad1)")
          )
          (footprint "Resistor_SMD:R_0805"
            (layer "F.Cu")
            (uuid "r1")
            (at 10 10 0)
            (property "Reference" "R1" (at 0 0 0) (layer "F.SilkS"))
            (pad "1" smd rect (at 0 0) (size 1 1) (layers "F.Cu" "F.Mask") (net 1 "Net-(R1-Pad1)") (uuid "r1-pad1"))
          )
          (footprint "Capacitor_SMD:C_0805"
            (layer "F.Cu")
            (uuid "c1")
            (at 30 10 0)
            (property "Reference" "C1" (at 0 0 0) (layer "F.SilkS"))
            (pad "1" smd rect (at 0 0) (size 1 1) (layers "F.Cu" "F.Mask") (net 1 "Net-(R1-Pad1)") (uuid "c1-pad1"))
          )
        )
        """.write(to: board, atomically: true, encoding: .utf8)
        return project
    }

    private func writeFailingKiCadCLI() throws -> URL {
        let directory = temporaryDirectory("failing-kicad-cli")
        let executable = directory.appendingPathComponent("kicad-cli")
        let script = """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output" ]; then
            shift
            mkdir -p "$(dirname "$1")"
            cat > "$1" <<'JSON'
        {"violations":[{"id":"drc-1","code":"clearance","severity":"error","message":"Track clearance is below rule.","refs":["R1","C1"]}]}
        JSON
          fi
          shift
        done
        exit 2
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    private func writeFailingNgspice() throws -> URL {
        let directory = temporaryDirectory("failing-ngspice")
        let executable = directory.appendingPathComponent("ngspice")
        let script = """
        #!/bin/sh
        output=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-o" ]; then
            shift
            output="$1"
          fi
          shift
        done
        mkdir -p "$(dirname "$output")"
        echo "fatal ngspice fixture error" > "$output"
        exit 3
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    private func writeHarnessArtifactPaths(drcReportPath: String) throws -> ElectronicsEvidenceArtifactPaths {
        let root = temporaryDirectory("tool-failure-harness-artifacts")
        let erc = try writeFixtureFile(name: "erc.json", text: #"{"violations":[]}"#, in: root)
        let scenario = try writeFixtureFile(
            name: "scenario.json",
            text: """
            {
              "scenario_id": "amp-low-voltage-output-stage",
              "design_id": "amp_low_voltage_audio",
              "circuit_path": "\(root.appendingPathComponent("output-stage.cir").path)",
              "analyses": ["tran", "ac"],
              "required_model_refs": ["MJ15003G"],
              "measurement_envelopes": [
                { "name": "output_power_w", "min": 24.0, "max": 28.0 },
                { "name": "thd_percent", "max": 1.0 }
              ]
            }
            """,
            in: root
        )
        _ = try writeFixtureFile(name: "output-stage.cir", text: "* amp output stage\n", in: root)
        let models = try writeFixtureFile(
            name: "models.json",
            text: #"[{"model_ref":"MJ15003G","legally_usable":true,"is_generic":false}]"#,
            in: root
        )
        let spice = try writeFixtureFile(name: "ngspice.log", text: "output_power_w = 25.1\nthd_percent = 0.72\n", in: root)
        let bom = try writeFixtureFile(
            name: "bom.json",
            text: """
            {
              "design_id": "amp_low_voltage_audio",
              "lines": [
                {
                  "line_id": "line-1",
                  "mpn": "RC0603FR-0710KL",
                  "quantity": 2,
                  "reference_designators": ["R1", "R2"]
                }
              ],
              "vendor_mappings": [
                {
                  "vendor_id": "digikey",
                  "line_id": "line-1",
                  "vendor_part_number": "311-10.0KHRCT-ND"
                }
              ],
              "substitutions": []
            }
            """,
            in: root
        )
        let availability = try writeFixtureFile(
            name: "availability.json",
            text: """
            [
              {
                "line_id": "line-1",
                "mpn": "RC0603FR-0710KL",
                "vendor_id": "digikey",
                "vendor_part_number": "311-10.0KHRCT-ND",
                "lifecycle": "active",
                "in_stock_quantity": 100,
                "unit_price_usd": 0.10,
                "source_url": "https://digikey.example/RC0603FR-0710KL"
              }
            ]
            """,
            in: root
        )
        let datasheetPDF = try writeFixtureFile(name: "rc0603.pdf", text: "%PDF-1.4\n", in: root)
        let datasheets = try writeFixtureFile(
            name: "datasheets.json",
            text: """
            [
              {
                "manufacturer": "Yageo",
                "mpn": "RC0603FR-0710KL",
                "url": "https://example.invalid/rc0603.pdf",
                "local_path": "\(datasheetPDF.path)",
                "sha256": "88f529ef82511e7d4cda07fd509e778ceef0a689da081729ffbd794a1d688cce",
                "provider_id": "digikey",
                "retrieved_at": "2026-06-07T00:00:00Z",
                "license": "cached-for-design-evidence",
                "citations": []
              }
            ]
            """,
            in: root
        )
        let vendorOrder = try writeFixtureFile(
            name: "vendor-order.json",
            text: #"{"status":"prepared","vendor_id":"Digi-Key","validated":true}"#,
            in: root
        )
        let gerbers = try writeFixtureFile(name: "gerbers.zip", text: "PK\u{03}\u{04}", in: root)
        let drill = try writeFixtureFile(name: "amp.drl", text: "M48\n", in: root)
        let pnp = try writeFixtureFile(name: "pnp.csv", text: "Designator,Mid X,Mid Y,Layer,Rotation\n", in: root)
        let drawing = try writeFixtureFile(name: "assembly-drawing.svg", text: "<svg><text>Assembly</text></svg>", in: root)
        let fabReport = try writeFixtureFile(name: "fab-report.json", text: #"{"status":"ok"}"#, in: root)
        let verification = try writeFixtureFile(name: "verification.json", text: #"{"status":"FAB_READY"}"#, in: root)
        let fabrication = try writeFixtureFile(
            name: "fabrication.json",
            text: """
            {
              "profile_id": "jlcpcb_2_layer",
              "outputs": [
                { "kind": "gerber_archive", "path": "\(gerbers.path)" },
                { "kind": "excellon_drill", "path": "\(drill.path)" },
                { "kind": "normalized_bom", "path": "\(bom.path)" },
                { "kind": "pick_and_place", "path": "\(pnp.path)" },
                { "kind": "assembly_drawing", "path": "\(drawing.path)" },
                { "kind": "fabrication_report", "path": "\(fabReport.path)" }
              ],
              "cam_report_path": "\(fabReport.path)"
            }
            """,
            in: root
        )

        return ElectronicsEvidenceArtifactPaths(
            ercReportPaths: [erc.path],
            drcReportPath: drcReportPath,
            spiceScenarioPath: scenario.path,
            spiceModelRecordsPath: models.path,
            ngspiceOutputPath: spice.path,
            normalizedBOMPath: bom.path,
            vendorAvailabilityPath: availability.path,
            datasheetEvidencePath: datasheets.path,
            vendorOrderPackagePath: vendorOrder.path,
            fabricationEvidencePath: fabrication.path,
            verificationReportPath: verification.path,
            releasePackagePath: nil,
            approvals: [],
            evidenceApprovals: [.highStakesSignoff]
        )
    }

    private func writeFixtureFile(name: String, text: String, in directory: URL? = nil) throws -> URL {
        let directory = directory ?? temporaryDirectory("tool-failure-fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func loadFixture<T: Decodable>(_ relativePath: String) throws -> T {
        try JSONDecoder().decode(
            T.self,
            from: Data(contentsOf: repoURL("plugins/electronics/fixtures").appendingPathComponent(relativePath))
        )
    }
}
