import XCTest
@testable import Merlin

final class PCBDRCFollowOnTests: XCTestCase {
    func testBoardProfileOutlineStackupNetClassesAndPlacementAreEvidence() throws {
        let circuitIR = fixtureCircuitIR()
        let profile = BoardProfile.jlcpcb2LayerDefault
        let candidate = PCBBoardPlanner().buildCandidate(
            circuitIR: circuitIR,
            boardProfile: profile,
            outline: BoardOutline(widthMm: 120, heightMm: 80),
            footprintResolutions: fixtureResolutions(for: circuitIR)
        )

        XCTAssertEqual(candidate.boardProfile.id, "jlcpcb_2layer_default")
        XCTAssertEqual(candidate.outline.widthMm, 120)
        XCTAssertEqual(candidate.boardProfile.stackup.map(\.name), ["F.Cu", "B.Cu"])
        XCTAssertTrue(candidate.netClassPlan.classes.keys.contains("audio_signal"))
        XCTAssertEqual(candidate.placementPlan.hints["Q1"], "respect thermal")
    }

    func testFootprintAssignmentRequiresPinCompatibilityProof() {
        let circuitIR = fixtureCircuitIR()
        var resolutions = fixtureResolutions(for: circuitIR)
        resolutions[0].issues = [
            KiCadLibraryResolutionIssue(code: "PIN_MISMATCH", message: "Pin does not match pad.", affectedRef: "Q1"),
        ]

        let result = FootprintAssignmentVerifier().verify(circuitIR: circuitIR, resolutions: resolutions)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "FOOTPRINT_PIN_PROOF_MISSING"))
    }

    func testDRCParserExtractsBlockingViolations() throws {
        let report = try KiCadDRCParser().parse(jsonData: drcJSON([
            drcViolation(id: "clearance-1", code: "clearance", severity: "error", message: "Clearance violation", refs: ["Q1", "R1"]),
            drcViolation(id: "silk-1", code: "silkscreen", severity: "warning", message: "Text near pad", refs: ["R1"]),
        ]))

        XCTAssertEqual(report.violations.count, 2)
        XCTAssertEqual(report.blockingViolations.map(\.id), ["clearance-1"])
    }

    func testDRCParserExtractsKiCad10SheetViolationsAndObjectItems() throws {
        let data = Data("""
        {
          "sheets": [
            {
              "path": "/",
              "violations": [
                {
                  "id": "drc-sheet-1",
                  "type": "unrouted_net",
                  "severity": "error",
                  "description": "Net is not fully routed.",
                  "items": [
                    { "ref": "J1" },
                    { "description": "Net-(J1-Pad1)" }
                  ]
                }
              ]
            }
          ]
        }
        """.utf8)

        let report = try KiCadDRCParser().parse(jsonData: data)

        XCTAssertEqual(report.blockingViolations.map(\.code), ["unrouted_net"])
        XCTAssertEqual(report.blockingViolations.first?.message, "Net is not fully routed.")
        XCTAssertEqual(report.blockingViolations.first?.refs, ["J1", "Net-(J1-Pad1)"])
    }

    func testDRCParserExtractsKiCad10UnconnectedItems() throws {
        let data = Data("""
        {
          "violations": [],
          "unconnected_items": [
            {
              "type": "unconnected_items",
              "severity": "error",
              "description": "Missing connection between items",
              "items": [
                { "description": "PTH pad 2 [NET1] of J1" },
                { "description": "PTH pad 1 [NET1] of R1" }
              ]
            }
          ]
        }
        """.utf8)

        let report = try KiCadDRCParser().parse(jsonData: data)

        XCTAssertEqual(report.blockingViolations.map(\.code), ["unconnected_items"])
        XCTAssertEqual(report.blockingViolations.first?.refs, ["PTH pad 2 [NET1] of J1", "PTH pad 1 [NET1] of R1"])
    }

    func testBoundedDRCRepairLoopRepairsSupportedClassesAndStopsAfterThreeAttempts() throws {
        let failing = try KiCadDRCParser().parse(jsonData: drcJSON([
            drcViolation(id: "place", code: "courtyards_overlap", severity: "error", message: "Courtyard overlap", refs: ["Q1", "R1"]),
            drcViolation(id: "route", code: "unrouted_net", severity: "error", message: "Unrouted net", refs: ["NET1"]),
        ]))

        let repaired = PCBDRCRepairLoop().run(drcReports: [failing, KiCadDRCReport(violations: [])])
        XCTAssertEqual(repaired.status, .verified)
        XCTAssertEqual(repaired.attempts, 1)
        XCTAssertEqual(repaired.appliedPatches.map(\.repairClass), [.placement, .routing])

        let exhausted = PCBDRCRepairLoop().run(drcReports: Array(repeating: failing, count: 5))
        XCTAssertEqual(exhausted.status, .blocked)
        XCTAssertEqual(exhausted.attempts, 3)
        XCTAssertTrue(exhausted.diagnostics.contains { $0.code == "DRC_REPAIR_ATTEMPTS_EXHAUSTED" })
    }

    func testUnsupportedDRCRepairBlocksWhenApprovalWouldBeRequired() throws {
        let report = try KiCadDRCParser().parse(jsonData: drcJSON([
            drcViolation(id: "layer", code: "layer_count_change_required", severity: "error", message: "Needs more layers", refs: ["board"]),
        ]))

        let result = PCBDRCRepairLoop().run(drcReports: [report])

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "DRC_REPAIR_REQUIRES_APPROVAL" })
    }

    func testPCBVerifiedRequiresEvidenceAndIsDistinctFromFabricationCompletion() {
        let missing = PCBVerificationGate().evaluate(.missingEvidence)
        XCTAssertEqual(missing.status, .blocked)
        XCTAssertTrue(missing.missingEvidence.contains(.schematicVerified))
        XCTAssertTrue(missing.missingEvidence.contains(.drcReport))

        let complete = PCBVerificationGate().evaluate(.complete)
        XCTAssertEqual(complete.status, .pcbVerified)
        XCTAssertEqual(complete.report.statusCode, "PCB_VERIFIED")
        XCTAssertFalse(complete.report.fabricationComplete)
    }

    private func fixtureCircuitIR() -> CircuitIR {
        CircuitIR(
            designId: "pcb-fixture",
            boardId: "audio",
            components: [
                component(refdes: "Q1", role: "output transistor", symbol: "Device:Q_NPN_BCE", footprint: "Package_TO_SOT_THT:TO-3P-3_Vertical", pins: ["B", "C", "E"]),
                component(refdes: "R1", role: "bias resistor", symbol: "Device:R", footprint: "Resistor_THT:R_Axial", pins: ["1", "2"]),
            ],
            nets: [
                CircuitNet(
                    name: "NET1",
                    role: "audio",
                    endpoints: [
                        CircuitNetEndpoint(componentRefdes: "Q1", pinNumber: "1"),
                        CircuitNetEndpoint(componentRefdes: "R1", pinNumber: "1"),
                    ],
                    netClass: "audio_signal",
                    safetyDomain: "isolated_secondary"
                ),
            ],
            constraints: [
                CircuitConstraint(kind: "placement", target: "Q1", value: "respect thermal"),
                CircuitConstraint(kind: "clearance", target: "NET1", value: "0.30mm"),
            ],
            verificationScenarios: []
        )
    }

    private func component(refdes: String, role: String, symbol: String, footprint: String, pins: [String]) -> CircuitComponent {
        CircuitComponent(
            refdes: refdes,
            role: role,
            selectedSymbol: symbol,
            selectedFootprint: footprint,
            manufacturerPartNumber: "\(refdes)-mpn",
            sourceEvidence: [SourceEvidence(kind: "datasheet", reference: "\(refdes) datasheet")],
            pins: pins.enumerated().map { index, pin in
                CircuitPin(
                    componentRefdes: refdes,
                    pinNumber: String(index + 1),
                    canonicalName: pin,
                    electricalType: "passive",
                    symbolPin: pin,
                    footprintPad: String(index + 1)
                )
            }
        )
    }

    private func fixtureResolutions(for circuitIR: CircuitIR) -> [KiCadLibraryPinResolution] {
        circuitIR.components.map { component in
            KiCadLibraryPinResolution(
                componentRefdes: component.refdes,
                symbolEvidence: KiCadSymbolDefinition(
                    name: component.selectedSymbol,
                    pins: component.pins.map {
                        KiCadSymbolPin(number: $0.pinNumber, name: $0.symbolPin, electricalType: $0.electricalType)
                    }
                ),
                footprintEvidence: KiCadFootprintDefinition(
                    name: component.selectedFootprint ?? "",
                    pads: component.pins.map {
                        KiCadFootprintPad(number: $0.footprintPad ?? "", name: $0.symbolPin)
                    }
                ),
                pinPadMap: Dictionary(uniqueKeysWithValues: component.pins.map { ($0.symbolPin, $0.footprintPad ?? "") }),
                issues: []
            )
        }
    }

    private func drcJSON(_ violations: [String]) -> Data {
        Data(#"{"violations":[\#(violations.joined(separator: ","))]}"#.utf8)
    }

    private func drcViolation(id: String, code: String, severity: String, message: String, refs: [String]) -> String {
        #"{"id":"\#(id)","code":"\#(code)","severity":"\#(severity)","message":"\#(message)","refs":\#(jsonArray(refs))}"#
    }

    private func jsonArray(_ values: [String]) -> String {
        "[\(values.map { #""\#($0)""# }.joined(separator: ","))]"
    }
}
