import XCTest
@testable import Merlin

@MainActor
final class DesignIntentApprovalFlowTests: XCTestCase {
    func testRequirementsDraftDesignIntentWithoutCreatingKiCadFiles() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let response = await send(
            runtime,
            capability: "kicad_build_intent_model",
            payload: #"{"design_id":"amp-low-voltage","requirements":"25W Class-A guitar amplifier low-voltage audio board"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "design_intent" })
        let intent = try JSONDecoder().decode(DesignIntent.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(intent.origin, .naturalLanguage)
        XCTAssertEqual(intent.approval.status, .draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("amp-low-voltage.kicad_sch").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("amp-low-voltage.kicad_pcb").path))
    }

    func testStructuredConstraintsPopulateDesignIntentInsteadOfEmptyDraft() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let constraints = """
        {
          "approval": "approved",
          "requirements": [
            "25W nominal pure single-ended Class-A output stage",
            "Isolated low-voltage secondary PCB only"
          ],
          "assumptions": ["120VAC mains primary remains off-board"],
          "pcb_secondary_only": true,
          "verification_plan": {
            "erc_required": true,
            "drc_required": true,
            "spice_required": true
          },
          "components": [
            {
              "refdes": "QOUT1",
              "role": "single-ended Class-A output transistor",
              "constraints": {
                "package": "TO-264",
                "power_dissipation": "external_heatsink_required"
              }
            }
          ],
          "nets": [
            {
              "name": "SPK_OUT",
              "role": "speaker output",
              "source": "QOUT1",
              "destination": "JSPK"
            }
          ]
        }
        """
        let constraintsLiteral = try jsonStringLiteral(constraints)

        let response = await send(
            runtime,
            capability: "kicad_build_intent_model",
            payload: #"{"design_id":"amp-low-voltage","title":"Amp Low Voltage Audio Board","constraints_json":\#(constraintsLiteral)}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "design_intent" })
        let intent = try JSONDecoder().decode(DesignIntent.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(intent.approval.status, .approved)
        XCTAssertEqual(intent.requirements.count, 2)
        XCTAssertEqual(intent.assumptions.count, 1)
        XCTAssertEqual(intent.boards.first?.safetyDomain, "isolated_secondary")
        XCTAssertTrue(intent.safetyProfile.isolationRequired)
        XCTAssertTrue(intent.verificationPlan.drcRequired)
        XCTAssertTrue(intent.verificationPlan.spiceRequired)
        XCTAssertEqual(intent.components.first?.refdes, "QOUT1")
        XCTAssertEqual(intent.nets.first?.name, "SPK_OUT")
    }

    func testConstraintOnlyPayloadSynthesizesReusableClassATopologyEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let constraints = #"{"topology":"single-ended_class_a","output_power_watts":25,"load_ohms":8,"mains_isolation":"transformer_isolated","mains_primary_offboard":true,"signal_path_components":"discrete_only","output_stage_components":"discrete_only","tone_bands":["bass","mid","treble"],"tone_control":"3_band_with_sweepable_boost_cut","pcb_domain":"secondary_side_only"}"#
        let constraintsLiteral = try jsonStringLiteral(constraints)

        let response = await send(
            runtime,
            capability: "kicad_build_intent_model",
            payload: #"{"board_profile_id":"ampdemo_classa_25w","input_artifact_path":"\#(root.appendingPathComponent("spec.md").path)","constraints_json":\#(constraintsLiteral)}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "design_intent" })
        let intent = try JSONDecoder().decode(DesignIntent.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(intent.designId, "ampdemo_classa_25w")
        XCTAssertTrue(intent.requirements.contains { $0.text.contains("topology: single-ended_class_a") })
        XCTAssertTrue(intent.requirements.contains { $0.text.contains("output_power_watts: 25") })
        XCTAssertTrue(intent.safetyProfile.isolationRequired)
        XCTAssertEqual(intent.boards.first?.safetyDomain, "isolated_secondary")
        XCTAssertEqual(intent.approval.status, .draft)
        XCTAssertTrue(intent.components.contains { $0.refdes == "JIN" && $0.role.contains("guitar input") })
        XCTAssertTrue(intent.components.contains { $0.refdes == "QPRE1" && $0.constraints["implementation"] == "discrete" })
        XCTAssertTrue(intent.components.contains { $0.refdes == "TONE1" && $0.constraints["bands"] == "bass,mid,treble" })
        XCTAssertTrue(intent.components.contains { $0.refdes == "FILTER1" && $0.role.contains("boost/cut") })
        XCTAssertTrue(intent.components.contains { $0.refdes == "QOUT1" && $0.role.contains("Class-A") })
        XCTAssertTrue(intent.components.contains { $0.refdes == "JSEC" && $0.constraints["mains_primary"] == "off_board" })
        XCTAssertTrue(intent.nets.contains { $0.name == "GUITAR_IN" && $0.source == "JIN" && $0.destination == "QPRE1" })
        XCTAssertTrue(intent.nets.contains { $0.name == "SPK_OUT" && $0.source == "QOUT1" && $0.destination == "JSPK" })
        XCTAssertTrue(intent.nets.contains { $0.name == "VRAW" && $0.role.contains("supply") })
        XCTAssertTrue(intent.verificationPlan.ercRequired)
        XCTAssertTrue(intent.verificationPlan.drcRequired)
        XCTAssertTrue(intent.verificationPlan.spiceRequired)
        XCTAssertTrue(intent.assumptions.contains { $0.text.contains("thermal") || $0.text.contains("heatsink") })
    }

    func testComponentSelectionConsumesSynthesizedTopologyEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let constraints = #"{"topology":"single-ended_class_a","output_power_watts":25,"load_ohms":8,"mains_isolation":"transformer_isolated","mains_primary_offboard":true,"signal_path_components":"discrete_only","output_stage_components":"discrete_only","tone_bands":["bass","mid","treble"],"tone_control":"3_band_with_sweepable_boost_cut","pcb_domain":"secondary_side_only"}"#
        let constraintsLiteral = try jsonStringLiteral(constraints)
        let intentResponse = await send(
            runtime,
            capability: "kicad_build_intent_model",
            payload: #"{"board_profile_id":"ampdemo_classa_25w","constraints_json":\#(constraintsLiteral)}"#
        )
        let intentArtifact = try XCTUnwrap(intentResponse.artifacts.first { $0.kind == "design_intent" })

        let response = await send(
            runtime,
            capability: "kicad_select_components",
            payload: #"{"design_id":"ampdemo_classa_25w","design_intent_path":"\#(intentArtifact.url.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try XCTUnwrap(response.artifacts.first { $0.kind == "component_matrix" })
        let data = try Data(contentsOf: matrix.url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let components = try XCTUnwrap(object["components"] as? [[String: Any]])
        XCTAssertTrue(components.contains { $0["refdes"] as? String == "QOUT1" })
        XCTAssertTrue(components.contains { $0["refdes"] as? String == "BR1" })
        XCTAssertTrue(components.allSatisfy { $0["selection_status"] as? String == "requires_vendor_resolution" })
    }

    func testApprovedClassATopologyGeneratesDiscreteCircuitIR() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let constraints = #"{"approval":"approved","topology":"single-ended_class_a","output_power_watts":25,"load_ohms":8,"mains_isolation":"transformer_isolated","mains_primary_offboard":true,"signal_path_components":"discrete_only","output_stage_components":"discrete_only","tone_bands":["bass","mid","treble"],"tone_control":"3_band_with_sweepable_boost_cut","pcb_domain":"secondary_side_only"}"#
        let constraintsLiteral = try jsonStringLiteral(constraints)
        let intentResponse = await send(
            runtime,
            capability: "kicad_build_intent_model",
            payload: #"{"board_profile_id":"ampdemo_classa_25w","constraints_json":\#(constraintsLiteral)}"#
        )
        let intentArtifact = try XCTUnwrap(intentResponse.artifacts.first { $0.kind == "design_intent" })

        let response = await send(
            runtime,
            capability: "kicad_generate_circuit_ir",
            payload: #"{"design_intent_path":"\#(intentArtifact.url.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "circuit_ir" })
        let circuitIR = try JSONDecoder().decode(CircuitIR.self, from: Data(contentsOf: artifact.url))
        let refdes = Set(circuitIR.components.map(\.refdes))
        XCTAssertFalse(refdes.contains("TONE1"))
        XCTAssertFalse(refdes.contains("FILTER1"))
        XCTAssertTrue(refdes.isSuperset(of: ["JIN", "QPRE1", "RBASS1", "CBASS1", "RMID1", "CMID1", "RTREBLE1", "CTREBLE1", "RFILT1", "CFILT1", "QDRV1", "QOUT1", "JSPK"]))
        XCTAssertTrue(circuitIR.components.allSatisfy { !$0.sourceEvidence.isEmpty })
        let intent = try JSONDecoder().decode(DesignIntent.self, from: Data(contentsOf: intentArtifact.url))
        let validation = ElectronicsSchemaValidator.validateReadyForKiCadMutation(designIntent: intent, circuitIR: circuitIR)
        XCTAssertTrue(validation.isValid, validation.issues.map(\.code).joined(separator: ","))
    }

    func testApprovalContinuationRequiresExplicitApproval() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(approval: DesignApproval(status: .draft), origin: .naturalLanguage), root: root)

        let response = await send(
            runtime,
            capability: "kicad_approve_design_intent",
            payload: #"{"design_intent_path":"\#(intentURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == "DESIGN_INTENT_EXPLICIT_APPROVAL_REQUIRED" })
        XCTAssertFalse(response.artifacts.contains { $0.kind == "design_intent" })
    }

    func testApprovalContinuationProducesApprovedIntentAndEnablesCircuitIR() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let constraints = #"{"topology":"single-ended_class_a","output_power_watts":25,"load_ohms":8,"mains_isolation":"transformer_isolated","mains_primary_offboard":true,"signal_path_components":"discrete_only","output_stage_components":"discrete_only","tone_bands":["bass","mid","treble"],"tone_control":"3_band_with_sweepable_boost_cut","pcb_domain":"secondary_side_only"}"#
        let constraintsLiteral = try jsonStringLiteral(constraints)
        let intentResponse = await send(
            runtime,
            capability: "kicad_build_intent_model",
            payload: #"{"board_profile_id":"ampdemo_classa_25w","constraints_json":\#(constraintsLiteral)}"#
        )
        let draftArtifact = try XCTUnwrap(intentResponse.artifacts.first { $0.kind == "design_intent" })
        let draft = try JSONDecoder().decode(DesignIntent.self, from: Data(contentsOf: draftArtifact.url))
        XCTAssertEqual(draft.approval.status, .draft)

        let blockedCircuitIR = await send(
            runtime,
            capability: "kicad_generate_circuit_ir",
            payload: #"{"design_intent_path":"\#(draftArtifact.url.path)"}"#
        )
        XCTAssertEqual(blockedCircuitIR.status, .blocked)
        XCTAssertTrue(blockedCircuitIR.diagnostics.contains { $0.code == "DESIGN_INTENT_NOT_APPROVED" })

        let approvalResponse = await send(
            runtime,
            capability: "kicad_approve_design_intent",
            payload: #"{"design_intent_path":"\#(draftArtifact.url.path)","approved":true,"approved_by":"jon","approved_at":"2026-05-30T17:00:00Z"}"#
        )

        XCTAssertEqual(approvalResponse.status, .ok)
        let approvedArtifact = try XCTUnwrap(approvalResponse.artifacts.first { $0.kind == "design_intent" })
        let approved = try JSONDecoder().decode(DesignIntent.self, from: Data(contentsOf: approvedArtifact.url))
        XCTAssertEqual(approved.approval.status, .approved)
        XCTAssertEqual(approved.approval.approvedBy, "jon")
        XCTAssertEqual(approved.approval.approvedAt, "2026-05-30T17:00:00Z")

        let circuitIRResponse = await send(
            runtime,
            capability: "kicad_generate_circuit_ir",
            payload: #"{"design_intent_path":"\#(approvedArtifact.url.path)"}"#
        )
        XCTAssertEqual(circuitIRResponse.status, .ok)
        XCTAssertTrue(circuitIRResponse.artifacts.contains { $0.kind == "circuit_ir" })
    }

    func testComponentSelectionBlocksWhenDesignIntentHasNoComponentEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(
            approval: DesignApproval(status: .approved),
            origin: .naturalLanguage,
            components: [],
            nets: []
        ), root: root)

        let response = await send(
            runtime,
            capability: "kicad_select_components",
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == ElectronicsBlockedReason.invalidInputQuality.rawValue })
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "COMPONENT_INTENT_REQUIRED" })
    }

    func testNaturalLanguageCompileBlocksWhenApprovedIntentHasNoConstructiveEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(
            approval: DesignApproval(status: .approved),
            origin: .naturalLanguage,
            components: [],
            nets: []
        ), root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await send(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == ElectronicsBlockedReason.invalidInputQuality.rawValue })
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "DESIGN_INTENT_INCOMPLETE" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("amp-low-voltage.kicad_sch").path))
    }

    func testUnapprovedNaturalLanguageIntentBlocksCompile() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(approval: DesignApproval(status: .draft), origin: .naturalLanguage), root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await send(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == "DESIGN_INTENT_NOT_APPROVED" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("amp-low-voltage.kicad_sch").path))
    }

    func testApprovedIntentCanProceedToCompileBoundary() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(approval: DesignApproval(
            status: .approved,
            approvedBy: "jon",
            approvedAt: "2026-05-29T13:30:00Z"
        )), root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await send(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        XCTAssertTrue(response.artifacts.contains { $0.kind == ElectronicsArtifactKind.kicadProject.rawValue })
    }

    func testRejectedIntentBlocksCompileWithDiagnostic() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(approval: DesignApproval(status: .rejected)), root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await send(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == "DESIGN_INTENT_REJECTED" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("amp-low-voltage.kicad_pro").path))
    }

    private func validIntent(
        approval: DesignApproval,
        origin: DesignIntentOrigin = .userAuthored,
        components: [ComponentIntent] = [
            ComponentIntent(refdes: "QOUT1", role: "output transistor", constraints: ["package": "TO-264"]),
        ],
        nets: [NetIntent] = [
            NetIntent(name: "SPK_OUT", role: "speaker output", source: "QOUT1", destination: "JSPK"),
        ]
    ) -> DesignIntent {
        DesignIntent(
            designId: "amp-low-voltage",
            title: "Amp Low Voltage Audio Board",
            origin: origin,
            approval: approval,
            requirements: [
                Requirement(id: "req-1", text: "Low-voltage audio board for 25W Class-A guitar amplifier", priority: "must"),
            ],
            assumptions: [],
            components: components,
            nets: nets,
            unresolvedDecisions: [],
            boards: [
                BoardIntent(id: "amp_low_voltage_audio", title: "Low Voltage Audio Board", safetyDomain: "isolated_secondary"),
            ],
            safetyProfile: SafetyProfile(isolationRequired: false, creepageMm: 0.0, notes: []),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: false, spiceRequired: true)
        )
    }

    private func writeIntent(_ intent: DesignIntent, root: URL) throws -> URL {
        let url = root.appendingPathComponent("\(intent.designId)-intent.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(intent).write(to: url)
        return url
    }

    private func send(
        _ runtime: WorkspaceRuntime,
        capability: String,
        payload: String
    ) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: capability),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? #""""#
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-design-intent-approval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
