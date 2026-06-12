import XCTest
@testable import Merlin

final class ElectronicsFinishCriteriaTests: XCTestCase {
    func testGenericSchematicAndPCBRealismProofCoversTwoMateriallyDifferentFixtures() throws {
        let fixtures = [
            genericSensorInterfaceFixture(),
            genericPowerSwitchFixture(),
        ]

        for circuitIR in fixtures {
            let output = temporaryDirectory("generic-realism-\(circuitIR.designId)")
            let schematicResult = try CircuitIRKiCadSchematicMaterializer().materialize(
                circuitIR: circuitIR,
                outputDirectory: output
            )
            let schematicText = try String(contentsOf: schematicResult.schematicURL, encoding: .utf8)
            let schematic = try KiCadSchematicParser().parse(schematicText)
            let schematicRealism = SchematicRealismValidator().validate(circuitIR: circuitIR, schematic: schematic)

            XCTAssertTrue(schematicRealism.isValid, "\(circuitIR.designId): \(schematicRealism.issues)")
            XCTAssertEqual(schematic.symbols.count, circuitIR.components.count, circuitIR.designId)
            XCTAssertFalse(schematic.wires.isEmpty, circuitIR.designId)
            XCTAssertTrue(schematicText.contains("ManufacturerPartNumber"), circuitIR.designId)
            XCTAssertTrue(schematicText.contains("SourceEvidence"), circuitIR.designId)
            XCTAssertFalse(schematicText.contains("AmpDemo"), circuitIR.designId)
            XCTAssertFalse(schematicText.contains("complete amplifier functional block"), circuitIR.designId)

            let boardResult = try CircuitIRKiCadBoardMaterializer().materialize(
                circuitIR: circuitIR,
                outputDirectory: output
            )
            let boardText = try String(contentsOf: boardResult.boardURL, encoding: .utf8)
            let warnings = KiCadBoardEvidenceChecker().warnings(
                circuitIR: circuitIR,
                boardText: boardText,
                boardPath: boardResult.boardURL.path
            )

            XCTAssertTrue(warnings.isEmpty, "\(circuitIR.designId): \(warnings)")
            XCTAssertTrue(boardText.contains(#""Edge.Cuts""#), circuitIR.designId)
            XCTAssertTrue(boardText.contains(#"(segment "#), circuitIR.designId)
            XCTAssertTrue(boardText.contains(#"(property "ManufacturerPartNumber""#), circuitIR.designId)
            XCTAssertTrue(boardText.contains(#"(property "SourceEvidence""#), circuitIR.designId)
            XCTAssertTrue(boardText.contains(#"(property "PinPadMap""#), circuitIR.designId)
            XCTAssertTrue(boardText.contains(#"(property "BoardID""#), circuitIR.designId)
            XCTAssertTrue(boardText.contains(#"(property "SafetyDomain""#), circuitIR.designId)
            XCTAssertFalse(boardText.contains("amp_low_voltage_audio"), circuitIR.designId)
            XCTAssertFalse(boardText.contains("amp_mains_power_supply"), circuitIR.designId)
        }
    }

    func testFullGenericArtifactChainGateBlocksNarrativeAndMissingGateEvidence() {
        var records = completeArtifactChainRecords()
        records.removeAll { $0.stage == .spiceScenario }
        records[0] = ElectronicsArtifactChainRecord(
            stage: .requirementsInspection,
            artifactPaths: [],
            evidenceSummary: "narrative claim that requirements were inspected"
        )
        records.append(ElectronicsArtifactChainRecord(
            stage: .drcRerun,
            artifactPaths: ["/tmp/drc-report.json"],
            evidenceSummary: "DRC repair rerun declared",
            repairMutationRequired: true,
            mutationEvidencePath: nil,
            rerunEvidencePath: "/tmp/drc-report.json"
        ))

        let result = ElectronicsArtifactChainGate().evaluate(records: records)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.missingStages.contains(.spiceScenario), "\(result)")
        XCTAssertTrue(result.diagnostics.contains { $0.code == "ARTIFACT_CHAIN_NARRATIVE_ONLY" }, "\(result)")
        XCTAssertTrue(result.diagnostics.contains { $0.code == "ARTIFACT_CHAIN_REPAIR_MUTATION_REQUIRED" }, "\(result)")
    }

    func testFullGenericArtifactChainGateAcceptsAllMajorArtifactBackedGates() {
        let result = ElectronicsArtifactChainGate().evaluate(records: completeArtifactChainRecords())

        XCTAssertTrue(result.isValid, "\(result)")
        XCTAssertTrue(result.missingStages.isEmpty, "\(result)")
        XCTAssertTrue(result.diagnostics.isEmpty, "\(result)")
    }

    func testFullGenericArtifactChainEvidenceIsEnforcedByEndToEndHarness() throws {
        let intent = genericApprovedIntent()
        let circuitIR = genericSensorInterfaceFixture()
        var completeEvidence = ElectronicsEndToEndEvidence.mainsPowerCADVerified
        completeEvidence.artifactChainRecords = completeArtifactChainRecords()
        completeEvidence.approvals = []
        completeEvidence.fabrication.approvals = []

        let complete = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: intent,
            circuitIR: circuitIR,
            outputDirectory: temporaryDirectory("generic-harness-complete-chain"),
            evidence: completeEvidence,
            approvals: []
        ))

        XCTAssertEqual(complete.status, .fabReady, "\(complete)")
        XCTAssertFalse(complete.missingEvidence.contains { $0.hasPrefix("artifact_chain:") }, "\(complete)")

        var incompleteEvidence = completeEvidence
        var incompleteRecords = completeArtifactChainRecords()
        incompleteRecords.removeAll { $0.stage == .bomVendorPackage }
        incompleteRecords[0] = ElectronicsArtifactChainRecord(
            stage: .requirementsInspection,
            artifactPaths: [],
            evidenceSummary: "narrative requirements inspection claim"
        )
        incompleteEvidence.artifactChainRecords = incompleteRecords

        let blocked = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: intent,
            circuitIR: circuitIR,
            outputDirectory: temporaryDirectory("generic-harness-blocked-chain"),
            evidence: incompleteEvidence,
            approvals: []
        ))

        XCTAssertEqual(blocked.status, .blocked, "\(blocked)")
        XCTAssertTrue(blocked.missingEvidence.contains("artifact_chain:bom_vendor_package"), "\(blocked)")
        XCTAssertTrue(blocked.diagnostics.contains { $0.code == "ARTIFACT_CHAIN_NARRATIVE_ONLY" }, "\(blocked)")
    }

    private func completeArtifactChainRecords() -> [ElectronicsArtifactChainRecord] {
        ElectronicsArtifactChainStage.allCases.map { stage in
            ElectronicsArtifactChainRecord(
                stage: stage,
                artifactPaths: ["/tmp/\(stage.rawValue).json"],
                evidenceSummary: "\(stage.rawValue) artifact-backed evidence",
                repairMutationRequired: [.ercRerun, .drcRerun, .spiceRun].contains(stage),
                mutationEvidencePath: [.ercRerun, .drcRerun, .spiceRun].contains(stage) ? "/tmp/\(stage.rawValue)-mutation.json" : nil,
                rerunEvidencePath: [.ercRerun, .drcRerun, .spiceRun].contains(stage) ? "/tmp/\(stage.rawValue)-rerun.json" : nil
            )
        }
    }

    private func genericSensorInterfaceFixture() -> CircuitIR {
        CircuitIR(
            designId: "generic_sensor_interface",
            boardId: "sensor_interface_low_voltage",
            components: [
                component(refdes: "J1", role: "sensor input connector", symbol: "Connector:Conn_01x02_Pin", footprint: "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical", mpn: "GEN-J1-2PIN", pins: ["1", "2"], safetyDomain: "isolated_secondary"),
                component(refdes: "R1", role: "input pull-up resistor", symbol: "Device:R", footprint: "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal", mpn: "GEN-R1-10K", pins: ["1", "2"], safetyDomain: "isolated_secondary"),
                component(refdes: "C1", role: "input filter capacitor", symbol: "Device:C", footprint: "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm", mpn: "GEN-C1-100N", pins: ["1", "2"], safetyDomain: "isolated_secondary"),
            ],
            nets: [
                net("SENSOR_SIG", "filtered sensor signal", "signal", "isolated_secondary", [("J1", "1"), ("R1", "1"), ("C1", "1")]),
                net("GND", "local reference", "power", "isolated_secondary", [("J1", "2"), ("C1", "2")]),
            ],
            constraints: [
                CircuitConstraint(kind: "placement", target: "J1", value: "place at board edge"),
                CircuitConstraint(kind: "clearance", target: "SENSOR_SIG", value: "0.25mm"),
            ],
            verificationScenarios: [
                VerificationScenario(id: "erc", kind: "erc", expectation: "no blocking ERC errors"),
            ]
        )
    }

    private func genericApprovedIntent() -> DesignIntent {
        DesignIntent(
            designId: "generic_sensor_interface",
            title: "Generic sensor interface",
            origin: .naturalLanguage,
            approval: DesignApproval(status: .approved, approvedBy: "test", approvedAt: "2026-06-07T00:00:00Z"),
            requirements: [
                Requirement(id: "REQ-1", text: "Create an isolated low-voltage sensor input interface with filtering.", priority: "must"),
            ],
            assumptions: [
                Assumption(id: "A-1", text: "All circuitry is isolated secondary low voltage.", rationale: "No hazardous mains domain is requested."),
            ],
            components: [],
            nets: [],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(
                    id: "sensor_interface_low_voltage",
                    title: "Sensor interface low-voltage board",
                    safetyDomain: "isolated_secondary",
                    verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: false)
                ),
            ],
            safetyProfile: SafetyProfile(isolationRequired: false, creepageMm: 0, notes: ["Low-voltage fixture"]),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: false)
        )
    }

    private func genericPowerSwitchFixture() -> CircuitIR {
        CircuitIR(
            designId: "generic_power_switch",
            boardId: "low_voltage_power_switch",
            components: [
                component(refdes: "Q1", role: "low-side MOSFET switch", symbol: "Transistor_FET:Q_NMOS_GDS", footprint: "Package_TO_SOT_THT:TO-220-3_Vertical", mpn: "GEN-Q1-NMOS", pins: ["G", "D", "S"], safetyDomain: "isolated_secondary"),
                component(refdes: "R1", role: "gate resistor", symbol: "Device:R", footprint: "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal", mpn: "GEN-R1-100R", pins: ["1", "2"], safetyDomain: "isolated_secondary"),
                component(refdes: "JLOAD", role: "load output connector", symbol: "Connector:Conn_01x02_Pin", footprint: "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical", mpn: "GEN-JLOAD-2PIN", pins: ["1", "2"], safetyDomain: "isolated_secondary"),
            ],
            nets: [
                net("GATE", "logic gate drive", "signal", "isolated_secondary", [("R1", "1"), ("Q1", "1")]),
                net("SW_NODE", "switched load return", "power", "isolated_secondary", [("Q1", "2"), ("JLOAD", "2")]),
                net("GND", "power reference", "power", "isolated_secondary", [("Q1", "3")]),
            ],
            constraints: [
                CircuitConstraint(kind: "placement", target: "Q1", value: "allow thermal clearance"),
                CircuitConstraint(kind: "clearance", target: "SW_NODE", value: "0.40mm"),
            ],
            verificationScenarios: [
                VerificationScenario(id: "erc", kind: "erc", expectation: "no blocking ERC errors"),
            ]
        )
    }

    private func component(
        refdes: String,
        role: String,
        symbol: String,
        footprint: String,
        mpn: String,
        pins: [String],
        safetyDomain: String
    ) -> CircuitComponent {
        CircuitComponent(
            refdes: refdes,
            role: role,
            selectedSymbol: symbol,
            selectedFootprint: footprint,
            manufacturerPartNumber: mpn,
            sourceEvidence: [
                SourceEvidence(kind: "datasheet", reference: "https://example.invalid/\(mpn).pdf"),
                SourceEvidence(kind: "catalog", reference: "fixture-catalog:\(mpn)"),
            ],
            pins: pins.enumerated().map { index, pin in
                CircuitPin(
                    componentRefdes: refdes,
                    pinNumber: String(index + 1),
                    canonicalName: pin,
                    electricalType: "passive",
                    symbolPin: pin,
                    footprintPad: String(index + 1)
                )
            },
            constraints: [
                "board_id": "low_voltage_generic",
                "safety_domain": safetyDomain,
                "footprint_pin_compatibility": "\(footprint) pads match \(pins.joined(separator: ","))",
            ]
        )
    }

    private func net(
        _ name: String,
        _ role: String,
        _ netClass: String,
        _ safetyDomain: String,
        _ endpoints: [(String, String)]
    ) -> CircuitNet {
        CircuitNet(
            name: name,
            role: role,
            endpoints: endpoints.map { CircuitNetEndpoint(componentRefdes: $0.0, pinNumber: $0.1) },
            netClass: netClass,
            safetyDomain: safetyDomain
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MerlinTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
