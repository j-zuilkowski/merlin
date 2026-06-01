import XCTest
@testable import Merlin

final class KiCadSchematicParserTests: XCTestCase {

    private let minimalFixture = """
    (kicad_sch
      (version 20250114)
      (generator "merlin")
      (uuid "root-uuid")
      (symbol
        (uuid "sym-1")
        (property "Reference" "R1")
        (property "Value" "10k")
        (property "Footprint" "Resistor_SMD:R_0603"))
      (wire (pts (xy 10 10) (xy 20 10)))
      (junction (at 20 10))
      (label "NET_LOCAL")
      (global_label "NET_GLOBAL")
      (hierarchical_label "NET_HIER")
      (sheet
        (uuid "sheet-1")
        (name "Power")
        (file "power.kicad_sch")
        (pin "VIN" input)
        (pin "VOUT" output)))
    """

    func test_parseMinimalSchematic_extractsTopLevelFields() throws {
        let document = try KiCadSchematicParser().parse(minimalFixture)
        XCTAssertEqual(document.version, 20250114)
        XCTAssertEqual(document.generator, "merlin")
        XCTAssertEqual(document.uuid, "root-uuid")
    }

    func test_symbolPropertyExtraction_extractsReferenceValueFootprint() throws {
        let document = try KiCadSchematicParser().parse(minimalFixture)
        let symbol = try XCTUnwrap(document.symbols.first)

        XCTAssertEqual(symbol.property(named: "Reference"), "R1")
        XCTAssertEqual(symbol.property(named: "Value"), "10k")
        XCTAssertEqual(symbol.property(named: "Footprint"), "Resistor_SMD:R_0603")
    }

    func test_wireAndJunctionExtraction_extractsGeometry() throws {
        let document = try KiCadSchematicParser().parse(minimalFixture)
        let wire = try XCTUnwrap(document.wires.first)
        let junction = try XCTUnwrap(document.junctions.first)

        XCTAssertEqual(wire.start.x, 10)
        XCTAssertEqual(wire.start.y, 10)
        XCTAssertEqual(wire.end.x, 20)
        XCTAssertEqual(wire.end.y, 10)
        XCTAssertEqual(junction.at.x, 20)
        XCTAssertEqual(junction.at.y, 10)
    }

    func test_hierarchicalLabelsAndSheetPins_arePreserved() throws {
        let document = try KiCadSchematicParser().parse(minimalFixture)

        XCTAssertTrue(document.labels.contains(where: { $0.kind == .local && $0.text == "NET_LOCAL" }))
        XCTAssertTrue(document.labels.contains(where: { $0.kind == .global && $0.text == "NET_GLOBAL" }))
        XCTAssertTrue(document.labels.contains(where: { $0.kind == .hierarchical && $0.text == "NET_HIER" }))

        let sheet = try XCTUnwrap(document.sheets.first)
        XCTAssertEqual(sheet.name, "Power")
        XCTAssertEqual(sheet.file, "power.kicad_sch")
        XCTAssertEqual(sheet.pins.map(\.name), ["VIN", "VOUT"])
    }

    func test_roundTripParseWriteParse_isStableForSupportedSubset() throws {
        let parser = KiCadSchematicParser()
        let writer = KiCadSchematicWriter()

        let first = try parser.parse(minimalFixture)
        let serialized = try writer.write(first)
        let second = try parser.parse(serialized)
        let third = try parser.parse(try writer.write(second))

        XCTAssertEqual(third, second)
    }

    func test_malformedSExpression_returnsTypedParserError() {
        let malformed = "(kicad_sch (version 20250114) (symbol (property \"Reference\" \"R1\")"

        XCTAssertThrowsError(try KiCadSchematicParser().parse(malformed)) { error in
            guard case KiCadSchematicParserError.malformed = error else {
                return XCTFail("Expected KiCadSchematicParserError.malformed, got \(error)")
            }
        }
    }
}
