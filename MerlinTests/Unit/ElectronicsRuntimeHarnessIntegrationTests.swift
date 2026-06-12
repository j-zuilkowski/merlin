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

        XCTAssertEqual(response.status, .ok, response.payload?.stringValue() ?? "\(response.diagnostics)")
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.diagnostics, [])
        XCTAssertEqual(result.status, .fabReady, "\(result)")
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

        XCTAssertEqual(response.status, .ok, response.payload?.stringValue() ?? "\(response.diagnostics)")
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .complete, "\(result)")
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
        let designIntentPath = try writeSeparatedDomainIntent(in: outputDirectory).path
        let circuitIRPath = try writeSeparatedCircuitIR(in: outputDirectory).path
        let evidenceData = try WorkspaceJSON.encoder.encode(evidence)
        let evidenceObject = try JSONSerialization.jsonObject(with: evidenceData)
        let object: [String: Any] = [
            "job_id": "amp-low-voltage-runtime",
            "design_intent_path": designIntentPath,
            "circuit_ir_path": circuitIRPath,
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
        let designIntentPath = try writeSeparatedDomainIntent(in: outputDirectory).path
        let circuitIRPath = try writeSeparatedCircuitIR(in: outputDirectory).path
        let artifactData = try WorkspaceJSON.encoder.encode(evidenceArtifacts)
        let artifactObject = try JSONSerialization.jsonObject(with: artifactData)
        let object: [String: Any] = [
            "job_id": "amp-low-voltage-artifacts",
            "design_intent_path": designIntentPath,
            "circuit_ir_path": circuitIRPath,
            "output_directory": outputDirectory.path,
            "evidence_artifacts": artifactObject,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func writeSeparatedDomainIntent(in root: URL) throws -> URL {
        try writeJSON(separatedDomainIntent(), name: "separated-design-intent.json", in: root)
    }

    private func writeSeparatedCircuitIR(in root: URL) throws -> URL {
        try writeJSON(lowVoltageControlCircuitIR(), name: "separated-circuit-ir.json", in: root)
    }

    private func separatedDomainIntent() -> DesignIntent {
        DesignIntent(
            designId: "generic_mixed_power_controller",
            title: "Generic mixed mains and low-voltage controller",
            origin: .naturalLanguage,
            approval: DesignApproval(status: .approved, approvedBy: "test", approvedAt: "2026-06-06T00:00:00Z"),
            requirements: [
                Requirement(id: "req-1", text: "Design a mains transformer supply and isolated low-voltage controller as separate safety domains.", priority: "must"),
            ],
            assumptions: [
                Assumption(id: "assume-1", text: "Hazardous mains and isolated low-voltage circuitry are separate board domains.", rationale: "Isolation boundary and review requirements differ."),
            ],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(
                    id: "mains_power",
                    title: "Mains transformer board",
                    safetyDomain: "mains_primary",
                    verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: false),
                    interBoardConnectors: [
                        InterBoardConnectorIntent(id: "JSEC", targetBoardId: "low_voltage_control", signalRole: "isolated secondary handoff"),
                    ]
                ),
                BoardIntent(
                    id: "low_voltage_control",
                    title: "Low voltage control board",
                    safetyDomain: "isolated_secondary",
                    verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true),
                    interBoardConnectors: [
                        InterBoardConnectorIntent(id: "JPRI", targetBoardId: "mains_power", signalRole: "isolated secondary handoff"),
                    ]
                ),
            ],
            safetyProfile: SafetyProfile(isolationRequired: true, creepageMm: 6.4, notes: ["Mains and isolated secondary domains are separated."]),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true)
        )
    }

    private func lowVoltageControlCircuitIR() -> CircuitIR {
        CircuitIR(
            designId: "generic_mixed_power_controller",
            boardId: "low_voltage_control",
            components: [
                CircuitComponent(
                    refdes: "Q1",
                    role: "low-voltage control transistor",
                    selectedSymbol: "Device:R",
                    selectedFootprint: "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",
                    manufacturerPartNumber: "2N3904",
                    sourceEvidence: [SourceEvidence(kind: "datasheet", reference: "2N3904 datasheet")],
                    pins: [
                        CircuitPin(componentRefdes: "Q1", pinNumber: "1", canonicalName: "B", electricalType: "input", symbolPin: "1", footprintPad: "1"),
                        CircuitPin(componentRefdes: "Q1", pinNumber: "2", canonicalName: "C", electricalType: "passive", symbolPin: "2", footprintPad: "2"),
                    ]
                ),
            ],
            nets: [
                CircuitNet(
                    name: "CTRL_IN",
                    role: "control input",
                    endpoints: [CircuitNetEndpoint(componentRefdes: "Q1", pinNumber: "1")],
                    netClass: "signal",
                    safetyDomain: "isolated_secondary"
                ),
            ],
            constraints: [],
            verificationScenarios: [
                VerificationScenario(id: "erc", kind: "erc", expectation: "no blocking ERC errors"),
                VerificationScenario(id: "spice", kind: "spice", expectation: "declared measurements pass envelopes"),
            ]
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, name: String, in root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        let data = try WorkspaceJSON.encoder.encode(value)
        try data.write(to: url, options: .atomic)
        return url
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
                "in_stock_quantity": 100,
                "unit_price_usd": 0.10,
                "source_url": "https://digikey.example/RC0603FR-0710KL"
              }
            ]
            """
        )
        let datasheetPDF = try write("rc0603.pdf", in: root, contents: "%PDF-1.4\n")
        let datasheets = try write(
            "datasheets.json",
            in: root,
            contents: """
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
            """
        )
        let vendorOrder = try write(
            "vendor-order.json",
            in: root,
            contents: #"{"status":"prepared","vendor_id":"Digi-Key","validated":true}"#
        )
        let gerbers = try write("gerbers.zip", in: root, contents: "PK\u{03}\u{04}")
        let drill = try write("amp.drl", in: root, contents: "M48\n")
        let pnp = try write("pnp.csv", in: root, contents: "Designator,Mid X,Mid Y,Layer,Rotation\n")
        let drawing = try write("assembly-drawing.svg", in: root, contents: "<svg><text>Assembly</text></svg>")
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
                { "kind": "assembly_drawing", "path": "\(drawing.path)" },
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
            datasheetEvidencePath: datasheets.path,
            vendorOrderPackagePath: vendorOrder.path,
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
