import XCTest
@testable import Merlin

@MainActor
final class ElectronicsRuntimeHarnessIntegrationTests: XCTestCase {
    func testRequirementsWorkflowReturnsFabReadyHarnessResultFromStructuredEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let payload = try harnessPayload(evidence: .ampLowVoltageVerified)
        XCTAssertNoThrow(try WorkspaceMessagePayload.jsonString(payload).decodeJSON(ElectronicsEndToEndWorkflowRequest.self))
        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.diagnostics, [])
        XCTAssertEqual(result.status, .fabReady)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.missingEvidence.contains("release_package"))
        XCTAssertTrue(result.missingEvidence.contains("release_approval"))
    }

    func testRequirementsWorkflowBlocksWhenHarnessMissingRequiredSPICEEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        var evidence = ElectronicsEndToEndEvidence.ampLowVoltageVerified
        evidence.spice = nil

        let payload = try harnessPayload(evidence: evidence)
        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.missingEvidence.contains("spice_measurements"))
        XCTAssertFalse(result.isComplete)
    }

    func testRequirementsWorkflowReturnsCompleteOnlyWithReleasePackageAndApproval() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        var evidence = ElectronicsEndToEndEvidence.ampLowVoltageVerified
        evidence.fabrication.releasePackagePath = "/tmp/amp-low-voltage/release.zip"
        evidence.fabrication.approvals.append(ElectronicsApprovalRecord(
            kind: .release,
            approvedBy: "test",
            summary: "Release package approved"
        ))

        let payload = try harnessPayload(evidence: evidence)
        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .complete)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.missingEvidence.isEmpty)
    }

    func testRequirementsWorkflowBuildsHarnessEvidenceFromArtifactPaths() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let outputDirectory = temporaryDirectory("runtime-artifact-harness")
        let artifactPaths = try writeCleanArtifactPaths(root: outputDirectory)
        let payload = try harnessPayload(evidenceArtifacts: artifactPaths, outputDirectory: outputDirectory)

        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.schematicStatus, .schematicVerified, "\(result)")
        XCTAssertEqual(result.pcbStatus, .pcbVerified, "\(result)")
        XCTAssertEqual(result.spiceStatus, .passed, "\(result)")
        XCTAssertEqual(result.fabricationStatus, .fabReady, "\(result)")
        XCTAssertEqual(result.diagnostics, [], "\(result)")
        XCTAssertEqual(result.status, .fabReady, "\(result)")
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.missingEvidence, ["release_package", "release_approval"], "\(result)")
    }

    func testRequirementsWorkflowBlocksNarrativeSPICELogFromArtifactPaths() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let outputDirectory = temporaryDirectory("runtime-narrative-spice")
        var artifactPaths = try writeCleanArtifactPaths(root: outputDirectory)
        artifactPaths.ngspiceOutputPath = try write(
            "ngspice-narrative.log",
            in: outputDirectory,
            contents: "SPICE completed successfully for the amplifier output stage.\n"
        ).path

        let response = await sendElectronics(
            runtime,
            capability: "workflow.requirements_to_pcb",
            payload: try harnessPayload(evidenceArtifacts: artifactPaths, outputDirectory: outputDirectory)
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.spiceStatus, .blocked)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "SPICE_MEASUREMENT_PARSE_FAILED" }, "\(result)")
        XCTAssertFalse(result.isComplete)
    }

    func testRequirementsWorkflowBlocksMissingSPICEModelRecordsArtifact() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let outputDirectory = temporaryDirectory("runtime-missing-spice-models")
        var artifactPaths = try writeCleanArtifactPaths(root: outputDirectory)
        artifactPaths.spiceModelRecordsPath = nil

        let response = await sendElectronics(
            runtime,
            capability: "workflow.requirements_to_pcb",
            payload: try harnessPayload(evidenceArtifacts: artifactPaths, outputDirectory: outputDirectory)
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.spiceStatus, .blocked)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "SPICE_MODEL_RECORDS_REQUIRED" }, "\(result)")
        XCTAssertFalse(result.isComplete)
    }

    func testRequirementsWorkflowBlocksSPICEScenarioMissingEnvelopesFromArtifactPaths() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let outputDirectory = temporaryDirectory("runtime-missing-spice-envelopes")
        var artifactPaths = try writeCleanArtifactPaths(root: outputDirectory)
        artifactPaths.spiceScenarioPath = try write(
            "scenario-missing-envelopes.json",
            in: outputDirectory,
            contents: """
            {
              "scenario_id": "amp-low-voltage-output-stage",
              "design_id": "amp_low_voltage_audio",
              "circuit_path": "\(outputDirectory.appendingPathComponent("output-stage.cir").path)",
              "analyses": ["tran", "ac"],
              "required_model_refs": ["MJ15003G"],
              "measurement_envelopes": []
            }
            """
        ).path

        let response = await sendElectronics(
            runtime,
            capability: "workflow.requirements_to_pcb",
            payload: try harnessPayload(evidenceArtifacts: artifactPaths, outputDirectory: outputDirectory)
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.spiceStatus, .blocked)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "SPICE_MEASUREMENT_ENVELOPE_REQUIRED" }, "\(result)")
        XCTAssertFalse(result.isComplete)
    }

    func testRequirementsWorkflowBlocksGenericSmokeSPICEDeckFromArtifactPaths() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let outputDirectory = temporaryDirectory("runtime-generic-spice-deck")
        var artifactPaths = try writeCleanArtifactPaths(root: outputDirectory)
        let smokeDeck = try write(
            "smoke.cir",
            in: outputDirectory,
            contents: """
            * generic smoke deck
            V1 in 0 DC 1
            R1 in 0 1k
            .op
            .end
            """
        )
        artifactPaths.spiceScenarioPath = try write(
            "smoke-scenario.json",
            in: outputDirectory,
            contents: """
            {
              "scenario_id": "amp-low-voltage-output-stage",
              "design_id": "amp_low_voltage_audio",
              "circuit_path": "\(smokeDeck.path)",
              "analyses": ["tran", "ac"],
              "required_model_refs": ["MJ15003G"],
              "measurement_envelopes": [
                { "name": "output_power_w", "min": 24.0, "max": 28.0 },
                { "name": "thd_percent", "max": 1.0 }
              ]
            }
            """
        ).path

        let response = await sendElectronics(
            runtime,
            capability: "workflow.requirements_to_pcb",
            payload: try harnessPayload(evidenceArtifacts: artifactPaths, outputDirectory: outputDirectory)
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.spiceStatus, .blocked)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "SPICE_CIRCUIT_DECK_GENERIC_SMOKE" }, "\(result)")
        XCTAssertFalse(result.isComplete)
    }

    private func harnessPayload(evidence: ElectronicsEndToEndEvidence) throws -> String {
        let outputDirectory = temporaryDirectory("runtime-harness")
        let evidenceData = try WorkspaceJSON.encoder.encode(evidence)
        let evidenceObject = try JSONSerialization.jsonObject(with: evidenceData)
        let object: [String: Any] = [
            "job_id": "amp-low-voltage-runtime",
            "design_intent_path": repoURL("plugins/electronics/fixtures/amp_low_voltage_audio/design_intent.json").path,
            "circuit_ir_path": repoURL("plugins/electronics/fixtures/amp_low_voltage_audio/circuit_ir.json").path,
            "output_directory": outputDirectory.path,
            "evidence": evidenceObject,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func harnessPayload(
        evidenceArtifacts: ElectronicsEvidenceArtifactPaths,
        outputDirectory: URL
    ) throws -> String {
        let artifactData = try WorkspaceJSON.encoder.encode(evidenceArtifacts)
        let artifactObject = try JSONSerialization.jsonObject(with: artifactData)
        let object: [String: Any] = [
            "job_id": "amp-low-voltage-artifacts",
            "design_intent_path": repoURL("plugins/electronics/fixtures/amp_low_voltage_audio/design_intent.json").path,
            "circuit_ir_path": repoURL("plugins/electronics/fixtures/amp_low_voltage_audio/circuit_ir.json").path,
            "output_directory": outputDirectory.path,
            "evidence_artifacts": artifactObject,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func writeCleanArtifactPaths(root: URL) throws -> ElectronicsEvidenceArtifactPaths {
        let erc = try write("erc.json", in: root, contents: #"{"violations":[]}"#)
        let drc = try write("drc.json", in: root, contents: #"{"violations":[]}"#)
        let scenario = try write(
            "scenario.json",
            in: root,
            contents: """
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
            """
        )
        _ = try write(
            "output-stage.cir",
            in: root,
            contents: """
            * amp output stage
            V1 in 0 SIN(0 1 1000)
            RLOAD out 0 8
            .tran 10u 10m
            .ac dec 10 20 20k
            .meas tran output_power_w PARAM='25.1'
            .meas tran thd_percent PARAM='0.72'
            .end
            """
        )
        let models = try write(
            "models.json",
            in: root,
            contents: #"[{"model_ref":"MJ15003G","legally_usable":true,"is_generic":false}]"#
        )
        let spice = try write("ngspice.log", in: root, contents: "output_power_w = 25.1\nthd_percent = 0.72\n")
        let bom = try write(
            "bom.json",
            in: root,
            contents: """
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
            """
        )
        let availability = try write(
            "availability.json",
            in: root,
            contents: """
            [
              {
                "line_id": "line-1",
                "mpn": "RC0603FR-0710KL",
                "vendor_id": "digikey",
                "vendor_part_number": "311-10.0KHRCT-ND",
                "lifecycle": "active",
                "in_stock_quantity": 100
              }
            ]
            """
        )
        let gerbers = try write("gerbers.zip", in: root, contents: "PK\u{03}\u{04}")
        let drill = try write("amp.drl", in: root, contents: "M48\n")
        let pnp = try write("pnp.csv", in: root, contents: "Designator,Mid X,Mid Y,Layer,Rotation\n")
        let fabReport = try write("fab-report.json", in: root, contents: #"{"status":"ok"}"#)
        let verification = try write("verification.json", in: root, contents: #"{"status":"FAB_READY"}"#)
        let fabrication = try write(
            "fabrication.json",
            in: root,
            contents: """
            {
              "profile_id": "jlcpcb_2_layer",
              "outputs": [
                { "kind": "gerber_archive", "path": "\(gerbers.path)" },
                { "kind": "excellon_drill", "path": "\(drill.path)" },
                { "kind": "normalized_bom", "path": "\(bom.path)" },
                { "kind": "pick_and_place", "path": "\(pnp.path)" },
                { "kind": "fabrication_report", "path": "\(fabReport.path)" }
              ],
              "cam_report_path": "\(fabReport.path)"
            }
            """
        )

        return ElectronicsEvidenceArtifactPaths(
            ercReportPaths: [erc.path],
            drcReportPath: drc.path,
            spiceScenarioPath: scenario.path,
            spiceModelRecordsPath: models.path,
            ngspiceOutputPath: spice.path,
            normalizedBOMPath: bom.path,
            vendorAvailabilityPath: availability.path,
            fabricationEvidencePath: fabrication.path,
            verificationReportPath: verification.path,
            releasePackagePath: nil,
            approvals: [],
            evidenceApprovals: [.highStakesSignoff]
        )
    }

    private func write(_ name: String, in root: URL, contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
