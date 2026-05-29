import XCTest
@testable import Merlin

final class CircuitIRToKiCadSchematicTests: XCTestCase {
    func testSchematicDocumentWriterRoundTripsCircuitFields() throws {
        let document = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: validCircuitIR())
        let serialized = try KiCadSchematicWriter().write(document)
        let parsed = try KiCadSchematicParser().parse(serialized)

        XCTAssertEqual(parsed.generator, "merlin-electronics")
        XCTAssertTrue(parsed.symbols.contains { symbol in
            symbol.property(named: "Reference") == "Q1"
                && symbol.property(named: "Symbol") == "Device:Q_NPN_BCE"
                && symbol.property(named: "Footprint") == "Package_TO_SOT_THT:TO-3P-3_Vertical"
        })
        XCTAssertTrue(parsed.labels.contains { $0.text == "DRV_OUT" })
    }

    func testValidCircuitIRCreatesKiCadProjectAndSchematic() throws {
        let outputDirectory = temporaryDirectory("circuit-ir-kicad")
        let result = try CircuitIRKiCadSchematicMaterializer().materialize(
            circuitIR: validCircuitIR(),
            outputDirectory: outputDirectory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.projectURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.schematicURL.path))
        XCTAssertEqual(result.sourceMap["Q1"], "circuit-component:Q1")

        let parsed = try KiCadSchematicParser().parse(String(contentsOf: result.schematicURL, encoding: .utf8))
        XCTAssertEqual(parsed.symbols.count, 2)
        XCTAssertEqual(parsed.labels.map(\.text).sorted(), ["DRV_OUT", "GND"])
    }

    func testParityPassesWhenCircuitIRMatchesSchematic() throws {
        let ir = validCircuitIR()
        let schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: ir)

        let result = CircuitIRSchematicParityChecker().check(circuitIR: ir, schematic: schematic)

        XCTAssertTrue(result.isValid, result.issues.map(\.message).joined(separator: "\n"))
    }

    func testParityFailsWhenComponentOrNetIsMissing() throws {
        let ir = validCircuitIR()
        var schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: ir)
        schematic.symbols.removeAll { $0.property(named: "Reference") == "Q2" }
        schematic.labels.removeAll { $0.text == "GND" }

        let result = CircuitIRSchematicParityChecker().check(circuitIR: ir, schematic: schematic)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "SCHEMATIC_COMPONENT_MISSING"))
        XCTAssertTrue(result.contains(code: "SCHEMATIC_NET_MISSING"))
    }

    func testSchematicMaterializerContainsNoProductSpecificEmitterShortcuts() throws {
        let source = try repoText("Merlin/Electronics/CircuitIRKiCadSchematicMaterializer.swift")

        for forbidden in ["AmpDemo", "ESP32", "25W", "Class-A", "MJ15003G"] {
            XCTAssertFalse(source.contains(forbidden), "Schematic materializer must stay product-generic; found \(forbidden)")
        }
    }

    private func validCircuitIR() -> CircuitIR {
        CircuitIR(
            designId: "generic-audio-board",
            boardId: "low_voltage_audio",
            components: [
                CircuitComponent(
                    refdes: "Q1",
                    role: "output transistor",
                    selectedSymbol: "Device:Q_NPN_BCE",
                    selectedFootprint: "Package_TO_SOT_THT:TO-3P-3_Vertical",
                    manufacturerPartNumber: "example-mpn-q1",
                    sourceEvidence: [SourceEvidence(kind: "datasheet", reference: "transistor datasheet")],
                    pins: [
                        CircuitPin(componentRefdes: "Q1", pinNumber: "1", canonicalName: "B", electricalType: "input", symbolPin: "B", footprintPad: "1"),
                        CircuitPin(componentRefdes: "Q1", pinNumber: "2", canonicalName: "C", electricalType: "power", symbolPin: "C", footprintPad: "2"),
                    ]
                ),
                CircuitComponent(
                    refdes: "Q2",
                    role: "driver transistor",
                    selectedSymbol: "Device:Q_NPN_BCE",
                    selectedFootprint: "Package_TO_SOT_THT:TO-92_Inline",
                    manufacturerPartNumber: "example-mpn-q2",
                    sourceEvidence: [SourceEvidence(kind: "datasheet", reference: "driver datasheet")],
                    pins: [
                        CircuitPin(componentRefdes: "Q2", pinNumber: "1", canonicalName: "B", electricalType: "input", symbolPin: "B", footprintPad: "1"),
                        CircuitPin(componentRefdes: "Q2", pinNumber: "2", canonicalName: "E", electricalType: "passive", symbolPin: "E", footprintPad: "2"),
                    ]
                ),
            ],
            nets: [
                CircuitNet(
                    name: "DRV_OUT",
                    role: "driver output",
                    endpoints: [
                        CircuitNetEndpoint(componentRefdes: "Q1", pinNumber: "1"),
                        CircuitNetEndpoint(componentRefdes: "Q2", pinNumber: "1"),
                    ],
                    netClass: "signal",
                    safetyDomain: "isolated_secondary"
                ),
                CircuitNet(
                    name: "GND",
                    role: "reference",
                    endpoints: [
                        CircuitNetEndpoint(componentRefdes: "Q2", pinNumber: "2"),
                    ],
                    netClass: "power",
                    safetyDomain: "isolated_secondary"
                ),
            ],
            constraints: [
                CircuitConstraint(kind: "placement", target: "Q1", value: "respect thermal clearance"),
            ],
            verificationScenarios: [
                VerificationScenario(id: "erc", kind: "erc", expectation: "no blocking ERC errors"),
            ]
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

    private func repoText(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
