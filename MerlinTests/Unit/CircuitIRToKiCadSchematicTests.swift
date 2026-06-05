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

    func testMaterializedCircuitIREmitsRealKiCadSymbolsAndConnectivity() throws {
        let document = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: validCircuitIR())
        let serialized = try KiCadSchematicWriter().write(document)
        let parsed = try KiCadSchematicParser().parse(serialized)

        XCTAssertTrue(serialized.contains(#"(lib_id "Transistor_BJT:Q_NPN_BCE")"#), serialized)
        XCTAssertTrue(serialized.contains(#"(label "DRV_OUT""#), serialized)
        XCTAssertTrue(serialized.contains(#"(symbol "Transistor_BJT:Q_NPN_BCE""#), serialized)
        XCTAssertTrue(serialized.contains(#"(pin "1""#), serialized)
        XCTAssertTrue(parsed.labels.contains { $0.text == "DRV_OUT" && $0.emitsKiCadConnectivity && $0.at != nil })
        XCTAssertTrue(parsed.labels.contains { $0.text == "GND" && $0.emitsKiCadConnectivity && $0.at != nil })
        XCTAssertTrue(parsed.symbols.contains { $0.property(named: "Reference") == "Q1" && $0.emitsKiCadSymbol })
        XCTAssertFalse(parsed.wires.isEmpty, "Multi-endpoint CircuitIR nets must emit physical wires, not labels only")
        XCTAssertFalse(parsed.labels.isEmpty)
    }

    func testMaterializedCircuitIRRunsRealKiCadERCAndReportsOnlyCircuitLevelGaps() throws {
        let kicadCLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
        guard FileManager.default.isExecutableFile(atPath: kicadCLI) else {
            throw XCTSkip("KiCad CLI is not installed at \(kicadCLI)")
        }
        let outputDirectory = temporaryDirectory("circuit-ir-real-erc")
        let result = try CircuitIRKiCadSchematicMaterializer().materialize(
            circuitIR: validCircuitIR(),
            outputDirectory: outputDirectory
        )
        let report = outputDirectory.appendingPathComponent("erc.json")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kicadCLI)
        process.arguments = ["sch", "erc", "--format", "json", "--output", report.path, result.schematicURL.path]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let reportText = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(reportText.contains(#""violations""#), reportText)
        XCTAssertFalse(reportText.contains(#""wire_dangling""#), reportText)
        XCTAssertFalse(reportText.contains(#""label_dangling""#), reportText)
        XCTAssertTrue(reportText.contains(#""pin_not_connected""#) || reportText.contains(#""pin_not_driven""#), reportText)
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
        XCTAssertEqual(Set(parsed.labels.map(\.text)), ["DRV_OUT", "GND"])
        XCTAssertEqual(parsed.wires.count, 1)
    }

    func testMultiEndpointNetDoesNotPlaceConnectivityLabelOnStarJunction() throws {
        let document = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: threeEndpointCircuitIR())
        let serialized = try KiCadSchematicWriter().write(document)
        let parsed = try KiCadSchematicParser().parse(serialized)

        XCTAssertEqual(parsed.wires.count, 2)
        XCTAssertFalse(
            parsed.labels.contains {
                $0.text == "DRV_OUT"
                    && $0.at == KiCadSchematicDocument.Point(x: 20.32, y: 25.4)
                    && $0.emitsKiCadConnectivity
            },
            "A KiCad label at a star-wire junction triggers label_multiple_wires ERC errors."
        )
        XCTAssertTrue(parsed.labels.contains { $0.text == "DRV_OUT" && $0.emitsKiCadConnectivity })
    }

    func testExplicitNoConnectRepairPatchEmitsRealKiCadNoConnectNode() throws {
        let schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: validCircuitIR())
        let updated = ERCRepairPatchApplier().apply([
            ERCRepairPatch(
                violationId: "erc-q1-c",
                repairClass: .explicitNoConnect,
                targetRef: "Symbol Q1 Pin 2 [C, Passive, Line]",
                action: "add_no_connect",
                details: "Pin not connected"
            ),
        ], to: schematic)

        let serialized = try KiCadSchematicWriter().write(updated)

        XCTAssertTrue(serialized.contains(#"(no_connect (at 27.94 20.32)"#), serialized)
        XCTAssertFalse(serialized.contains(#"(merlin_erc_repair"#), serialized)
        XCTAssertNoThrow(try KiCadSchematicParser().parse(serialized))
    }

    func testMaterializationBlocksWhenKiCadPinGeometryCannotBeResolved() throws {
        var circuitIR = validCircuitIR()
        circuitIR.components[0].selectedSymbol = "Missing:NoSuchSymbol"
        let outputDirectory = temporaryDirectory("circuit-ir-missing-pin-geometry")

        XCTAssertThrowsError(try CircuitIRKiCadSchematicMaterializer().materialize(
            circuitIR: circuitIR,
            outputDirectory: outputDirectory
        )) { error in
            guard case CircuitIRKiCadSchematicMaterializerError.unresolvedPinGeometry(let issues) = error else {
                return XCTFail("Expected unresolved pin geometry error, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.code == "PIN_GEOMETRY_UNRESOLVED" })
        }
    }

    func testKiCadSymbolGeometryResolverExtractsPinLocationsFromInstalledLibraries() throws {
        let roots = KiCadLibraryRootDiscovery().discover()
        guard roots != nil else {
            throw XCTSkip("KiCad libraries are not installed")
        }

        let geometry = try XCTUnwrap(KiCadSymbolGeometryResolver(roots: roots).resolve(libraryID: "Device:R"))

        XCTAssertEqual(geometry.libraryID, "Device:R")
        XCTAssertTrue(geometry.pins.contains { $0.number == "1" && $0.at == KiCadSchematicDocument.Point(x: 0, y: 3.81) })
        XCTAssertTrue(geometry.pins.contains { $0.number == "2" && $0.at == KiCadSchematicDocument.Point(x: 0, y: -3.81) })
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
        for forbidden in ["q_npn", "bridge_rectifier", "potentiometer"] {
            XCTAssertFalse(source.lowercased().contains(forbidden), "Schematic materializer must use library pin geometry, not symbol-name offset shortcuts")
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
                        CircuitPin(componentRefdes: "Q2", pinNumber: "3", canonicalName: "E", electricalType: "passive", symbolPin: "E", footprintPad: "3"),
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
                        CircuitNetEndpoint(componentRefdes: "Q2", pinNumber: "3"),
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

    private func threeEndpointCircuitIR() -> CircuitIR {
        var ir = validCircuitIR()
        ir.components.append(CircuitComponent(
            refdes: "Q3",
            role: "third transistor",
            selectedSymbol: "Device:Q_NPN_BCE",
            selectedFootprint: "Package_TO_SOT_THT:TO-92_Inline",
            manufacturerPartNumber: "example-mpn-q3",
            sourceEvidence: [SourceEvidence(kind: "datasheet", reference: "third datasheet")],
            pins: [
                CircuitPin(componentRefdes: "Q3", pinNumber: "1", canonicalName: "B", electricalType: "input", symbolPin: "B", footprintPad: "1"),
            ]
        ))
        ir.nets[0].endpoints.append(CircuitNetEndpoint(componentRefdes: "Q3", pinNumber: "1"))
        return ir
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
