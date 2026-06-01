import XCTest
@testable import Merlin

final class ERCRepairLoopTests: XCTestCase {
    func testERCJSONParserExtractsStructuredViolations() throws {
        let report = try KiCadERCParser().parse(jsonData: ercJSON([
            ercViolation(id: "v1", code: "no_connect", severity: "error", message: "Pin is not connected", refs: ["J1.1"]),
            ercViolation(id: "v2", code: "info_only", severity: "warning", message: "Annotation warning", refs: ["R1"]),
        ]))

        XCTAssertEqual(report.violations.count, 2)
        XCTAssertEqual(report.violations[0].id, "v1")
        XCTAssertEqual(report.violations[0].code, "no_connect")
        XCTAssertEqual(report.violations[0].severity, .error)
        XCTAssertEqual(report.blockingViolations.map(\.id), ["v1"])
    }

    func testERCJSONParserExtractsKiCad10SheetViolations() throws {
        let data = Data("""
        {
          "sheets": [
            {
              "path": "/",
              "violations": [
                {
                  "type": "pin_not_connected",
                  "severity": "error",
                  "description": "Pin not connected",
                  "items": [
                    { "description": "Symbol R1 Pin 1 [Passive, Line]", "uuid": "abc" }
                  ]
                },
                {
                  "type": "unconnected_wire_endpoint",
                  "severity": "warning",
                  "description": "Unconnected wire endpoint",
                  "items": []
                }
              ]
            }
          ]
        }
        """.utf8)

        let report = try KiCadERCParser().parse(jsonData: data)

        XCTAssertEqual(report.violations.map(\.code), ["pin_not_connected", "unconnected_wire_endpoint"])
        XCTAssertEqual(report.violations[0].message, "Pin not connected")
        XCTAssertEqual(report.violations[0].refs, ["Symbol R1 Pin 1 [Passive, Line]"])
        XCTAssertEqual(report.blockingViolations.map(\.code), ["pin_not_connected"])
    }

    func testPlannerSupportsAllowedFirstMilestoneRepairClasses() throws {
        let report = try KiCadERCParser().parse(jsonData: ercJSON([
            ercViolation(id: "nc", code: "no_connect", severity: "error", message: "Add explicit no-connect", refs: ["J1.2"]),
            ercViolation(id: "pf", code: "power_flag_missing", severity: "error", message: "Power input is not driven", refs: ["+VRAW"]),
            ercViolation(id: "nl", code: "net_label_mismatch", severity: "error", message: "Net label mismatch", refs: ["DRV_OUT"]),
            ercViolation(id: "ep", code: "missing_connection", severity: "error", message: "Known endpoint is disconnected", refs: ["Q1.1"]),
            ercViolation(id: "pm", code: "pin_mapping_mismatch", severity: "error", message: "Pin mapping differs from resolver evidence", refs: ["Q1.2"]),
        ]))

        let plan = ERCRepairPlanner().planRepairs(
            report: report,
            circuitIR: validCircuitIR(),
            resolverEvidence: [provenPinResolution()]
        )

        XCTAssertTrue(plan.isRepairable)
        XCTAssertEqual(plan.patches.map(\.repairClass), [
            .explicitNoConnect,
            .powerFlag,
            .netLabelMismatch,
            .knownEndpointConnection,
            .pinMappingCorrection,
        ])
    }

    func testUnsupportedERCViolationBlocksRepair() throws {
        let report = try KiCadERCParser().parse(jsonData: ercJSON([
            ercViolation(id: "x", code: "pin_conflict", severity: "error", message: "Output pins fight", refs: ["U1.1", "U2.1"]),
        ]))

        let plan = ERCRepairPlanner().planRepairs(report: report, circuitIR: validCircuitIR(), resolverEvidence: [])

        XCTAssertFalse(plan.isRepairable)
        XCTAssertEqual(plan.unsupportedViolations.map(\.code), ["pin_conflict"])
    }

    func testPlannerClassifiesGeneratedArtifactAndIncompleteCircuitFailures() throws {
        let report = try KiCadERCParser().parse(jsonData: ercJSON([
            ercViolation(id: "wire", code: "wire_dangling", severity: "error", message: "Generated wire is not attached", refs: ["DRV_OUT"]),
            ercViolation(id: "drive", code: "pin_not_driven", severity: "error", message: "Input pin lacks driver", refs: ["Q1.1"]),
        ]))

        let plan = ERCRepairPlanner().planRepairs(
            report: report,
            circuitIR: validCircuitIR(),
            resolverEvidence: []
        )

        XCTAssertTrue(plan.isRepairable)
        XCTAssertEqual(plan.patches.map(\.repairClass), [.generatedArtifactBug, .incompleteCircuit])
        XCTAssertEqual(plan.patches.map(\.action), ["regenerate_schematic_from_pin_geometry", "complete_or_correct_circuit_ir"])
    }


    func testRepairLoopStopsAfterThreeIterations() throws {
        let failing = try KiCadERCParser().parse(jsonData: ercJSON([
            ercViolation(id: "nc", code: "no_connect", severity: "error", message: "Add explicit no-connect", refs: ["J1.2"]),
        ]))
        let sequence = Array(repeating: failing, count: 5)

        let result = ERCRepairLoop().run(
            initialSchematic: schematic(),
            circuitIR: validCircuitIR(),
            ercReports: sequence,
            resolverEvidence: []
        )

        XCTAssertEqual(result.attempts, 3)
        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "ERC_REPAIR_ATTEMPTS_EXHAUSTED" })
    }

    func testRepairLoopPassesWhenRerunReportHasNoBlockingViolations() throws {
        let failing = try KiCadERCParser().parse(jsonData: ercJSON([
            ercViolation(id: "nc", code: "no_connect", severity: "error", message: "Add explicit no-connect", refs: ["J1.2"]),
        ]))
        let passing = KiCadERCReport(violations: [])

        let result = ERCRepairLoop().run(
            initialSchematic: schematic(),
            circuitIR: validCircuitIR(),
            ercReports: [failing, passing],
            resolverEvidence: []
        )

        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.attempts, 1)
        XCTAssertTrue(result.appliedPatches.contains { $0.repairClass == .explicitNoConnect })
    }

    private func schematic() -> KiCadSchematicDocument {
        CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: validCircuitIR())
    }

    private func validCircuitIR() -> CircuitIR {
        CircuitIR(
            designId: "schematic-check",
            boardId: "control_board",
            components: [
                CircuitComponent(
                    refdes: "Q1",
                    role: "switch",
                    selectedSymbol: "Device:Q_NPN_BCE",
                    selectedFootprint: "Package_TO_SOT_THT:TO-92_Inline",
                    manufacturerPartNumber: "example-mpn",
                    sourceEvidence: [SourceEvidence(kind: "datasheet", reference: "transistor datasheet")],
                    pins: [
                        CircuitPin(componentRefdes: "Q1", pinNumber: "1", canonicalName: "B", electricalType: "input", symbolPin: "B", footprintPad: "1"),
                        CircuitPin(componentRefdes: "Q1", pinNumber: "2", canonicalName: "C", electricalType: "power", symbolPin: "C", footprintPad: "2"),
                    ]
                ),
                CircuitComponent(
                    refdes: "J1",
                    role: "connector",
                    selectedSymbol: "Connector:Conn_01x02_Pin",
                    selectedFootprint: "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical",
                    manufacturerPartNumber: "example-connector",
                    sourceEvidence: [SourceEvidence(kind: "datasheet", reference: "connector datasheet")],
                    pins: [
                        CircuitPin(componentRefdes: "J1", pinNumber: "1", canonicalName: "IN", electricalType: "passive", symbolPin: "Pin_1", footprintPad: "1"),
                        CircuitPin(componentRefdes: "J1", pinNumber: "2", canonicalName: "NC", electricalType: "passive", symbolPin: "Pin_2", footprintPad: "2"),
                    ]
                ),
            ],
            nets: [
                CircuitNet(
                    name: "DRV_OUT",
                    role: "drive signal",
                    endpoints: [
                        CircuitNetEndpoint(componentRefdes: "Q1", pinNumber: "1"),
                        CircuitNetEndpoint(componentRefdes: "J1", pinNumber: "1"),
                    ],
                    netClass: "signal",
                    safetyDomain: "low_voltage"
                ),
            ],
            constraints: [],
            verificationScenarios: [VerificationScenario(id: "erc", kind: "erc", expectation: "no blocking ERC errors")]
        )
    }

    private func provenPinResolution() -> KiCadLibraryPinResolution {
        KiCadLibraryPinResolution(
            componentRefdes: "Q1",
            symbolEvidence: KiCadSymbolDefinition(
                name: "Device:Q_NPN_BCE",
                pins: [
                    KiCadSymbolPin(number: "1", name: "B", electricalType: "input"),
                    KiCadSymbolPin(number: "2", name: "C", electricalType: "power"),
                ]
            ),
            footprintEvidence: KiCadFootprintDefinition(
                name: "Package_TO_SOT_THT:TO-92_Inline",
                pads: [
                    KiCadFootprintPad(number: "1", name: "B"),
                    KiCadFootprintPad(number: "2", name: "C"),
                ]
            ),
            pinPadMap: ["B": "1", "C": "2"],
            issues: []
        )
    }

    private func ercJSON(_ violations: [String]) -> Data {
        Data(#"{"violations":[\#(violations.joined(separator: ","))]}"#.utf8)
    }

    private func ercViolation(
        id: String,
        code: String,
        severity: String,
        message: String,
        refs: [String]
    ) -> String {
        #"{"id":"\#(id)","code":"\#(code)","severity":"\#(severity)","message":"\#(message)","refs":\#(jsonArray(refs))}"#
    }

    private func jsonArray(_ values: [String]) -> String {
        let encoded = values.map { #""\#($0)""# }.joined(separator: ",")
        return "[\(encoded)]"
    }
}
