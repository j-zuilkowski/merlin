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
        XCTAssertFalse(reportText.contains(#""label_multiple_wires""#), reportText)
        XCTAssertFalse(reportText.contains(#""multiple_net_names""#), reportText)
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
        XCTAssertEqual(parsed.wires.count, 3)
    }

    func testMultiEndpointNetDoesNotPlaceConnectivityLabelOnStarJunction() throws {
        let document = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: threeEndpointCircuitIR())
        let serialized = try KiCadSchematicWriter().write(document)
        let parsed = try KiCadSchematicParser().parse(serialized)

        XCTAssertEqual(parsed.wires.count, 4)
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

    func testBundledSymbolGeometrySupportsCIMaterializationWithoutInstalledLibraries() throws {
        let resolver = KiCadSymbolGeometryResolver(roots: nil, cache: KiCadSymbolGeometryCache())

        XCTAssertNotNil(resolver.resolve(libraryID: "Device:R")?.pin(number: "1", name: "1"))
        XCTAssertEqual(resolver.resolve(libraryID: "Device:Q_NPN_BCE")?.libraryID, "Transistor_BJT:Q_NPN_BCE")
        XCTAssertNotNil(resolver.resolve(libraryID: "Connector:AudioJack2")?.pin(number: "T", name: "T"))
        XCTAssertNotNil(resolver.resolve(libraryID: "Device:D_Bridge_+-AA")?.pin(number: "1", name: "+"))
        XCTAssertEqual(resolver.resolve(libraryID: "Device:Q_NJFET_DSG")?.libraryID, "Transistor_FET:Q_NJFET_DSG")
        XCTAssertNotNil(resolver.resolve(libraryID: "Transistor_FET:Q_NMOS_GDS")?.pin(number: "1", name: "G"))
        XCTAssertNil(resolver.resolve(libraryID: "Missing:NoSuchSymbol"))

        let embeddedSymbols = KiCadEmbeddedSymbolLibraryBuilder(roots: nil).libSymbolsNode(for: [
            "Device:Q_NPN_BCE",
            "Device:Q_NJFET_DSG",
            "Missing:NoSuchSymbol",
        ])
        let embeddedText = try KiCadSchematicWriter().write(KiCadSchematicDocument(
            version: 20230121,
            generator: "merlin-tests",
            uuid: UUID().uuidString,
            symbols: [],
            wires: [],
            junctions: [],
            labels: [],
            sheets: [],
            opaqueNodes: [embeddedSymbols]
        ))
        XCTAssertTrue(embeddedText.contains(#"(symbol "Transistor_BJT:Q_NPN_BCE""#), embeddedText)
        XCTAssertTrue(embeddedText.contains(#"(symbol "Transistor_FET:Q_NJFET_DSG""#), embeddedText)
        XCTAssertFalse(embeddedText.contains(#"(symbol "Missing:NoSuchSymbol""#), embeddedText)

        let outputDirectory = temporaryDirectory("circuit-ir-ci-bundled-geometry")
        let result = try CircuitIRKiCadSchematicMaterializer(pinGeometryResolver: resolver).materialize(
            circuitIR: validCircuitIR(),
            outputDirectory: outputDirectory
        )

        let parsed = try KiCadSchematicParser().parse(String(contentsOf: result.schematicURL, encoding: .utf8))
        XCTAssertEqual(parsed.wires.count, 3)
        XCTAssertTrue(parsed.labels.contains { $0.text == "DRV_OUT" && $0.emitsKiCadConnectivity })
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

    func testSchematicRealismValidatorPassesMaterializedDiscreteCircuitIR() throws {
        let ir = validCircuitIR()
        let schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: ir)

        let result = SchematicRealismValidator().validate(circuitIR: ir, schematic: schematic)

        XCTAssertTrue(result.isValid, result.issues.map(\.message).joined(separator: "\n"))
    }

    func testSchematicRealismValidatorRejectsCompositeMetadataOnlyCaricature() throws {
        let ir = validCircuitIR()
        let schematic = KiCadSchematicDocument(
            version: 20240101,
            generator: "merlin-preview",
            uuid: "composite",
            symbols: [
                KiCadSchematicDocument.Symbol(
                    uuid: nil,
                    properties: [
                        "Reference": "AMP1",
                        "Symbol": "Merlin:AmplifierBlock",
                        "Role": "complete amplifier block",
                        "Source": "narrative",
                        "Pins": "1:IN:IN,2:OUT:OUT",
                    ],
                    emitsKiCadSymbol: false
                ),
            ],
            wires: [],
            junctions: [],
            labels: ir.nets.map {
                KiCadSchematicDocument.Label(kind: .local, text: $0.name, emitsKiCadConnectivity: false)
            },
            sheets: [],
            opaqueNodes: []
        )

        let result = SchematicRealismValidator().validate(circuitIR: ir, schematic: schematic)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "SCHEMATIC_KICAD_VERSION_STALE"))
        XCTAssertTrue(result.contains(code: "SCHEMATIC_GENERATOR_MISMATCH"))
        XCTAssertTrue(result.contains(code: "SCHEMATIC_COMPONENT_MISSING"))
        XCTAssertTrue(result.contains(code: "SCHEMATIC_COMPOSITE_BLOCK"))
        XCTAssertTrue(result.contains(code: "SCHEMATIC_NET_CONNECTIVITY_MISSING"))
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

    func testMaterializersCarryGenericBoardAndSafetyDomainProvenance() throws {
        let circuitIR = boardScopedCircuitIR()
        let schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: circuitIR)
        let serializedSchematic = try KiCadSchematicWriter().write(schematic)

        XCTAssertTrue(serializedSchematic.contains(#""BoardID" "low_voltage_control""#), serializedSchematic)
        XCTAssertTrue(serializedSchematic.contains(#""SafetyDomain" "isolated_secondary""#), serializedSchematic)

        let outputDirectory = temporaryDirectory("board-domain-provenance")
        let board = try CircuitIRKiCadBoardMaterializer().materialize(
            circuitIR: circuitIR,
            outputDirectory: outputDirectory
        )
        let boardText = try String(contentsOf: board.boardURL, encoding: .utf8)

        XCTAssertTrue(boardText.contains(#"(property "BoardID" "low_voltage_control""#), boardText)
        XCTAssertTrue(boardText.contains(#"(property "SafetyDomain" "isolated_secondary""#), boardText)
    }

    func testSchematicWriterHidesEvidenceFieldsThatObscureUsableSymbols() throws {
        let circuitIR = boardScopedCircuitIR()
        let schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: circuitIR)
        let serialized = try KiCadSchematicWriter().write(schematic)

        let hiddenFields = [
            ("BoardID", "low_voltage_control"),
            ("Footprint", "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal"),
            ("ManufacturerPartNumber", "example-resistor"),
            ("SafetyDomain", "isolated_secondary"),
        ]
        for (field, value) in hiddenFields {
            let property = try XCTUnwrap(
                propertyNode(named: field, value: value, in: serialized),
                "Missing \(field) property in schematic output."
            )
            XCTAssertTrue(
                property.contains(" hide)"),
                "\(field) must remain machine-readable but hidden so visual schematic evidence keeps symbols and connectors readable.\n\(serialized)"
            )
        }
    }

    func testSchematicWriterKeepsHumanLabelsNearTheirSymbol() throws {
        let circuitIR = boardScopedCircuitIR()
        let schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: circuitIR)
        let serialized = try KiCadSchematicWriter().write(schematic)

        let symbol = try XCTUnwrap(schematic.symbols.first)
        let symbolPoint = try XCTUnwrap(symbol.at)
        for (field, value) in [("Reference", "RPU"), ("Value", "10kOhm")] {
            let property = try XCTUnwrap(propertyNode(named: field, value: value, in: serialized))
            let propertyPoint = try XCTUnwrap(point(inPropertyNode: property))
            XCTAssertLessThanOrEqual(
                abs(propertyPoint.y - symbolPoint.y),
                6.0,
                "\(field) text should stay near the symbol body instead of being pushed away by hidden evidence fields."
            )
        }
    }

    func testSchematicMaterializerKeepsLargeDiscreteCircuitInsideVisibleSheetArea() throws {
        let schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: largeConnectorCircuitIR())
        let points = schematic.symbols.compactMap(\.at)

        XCTAssertEqual(points.count, 21)
        XCTAssertLessThanOrEqual(
            points.map(\.y).max() ?? 0,
            152.4,
            "Large generated schematics must keep connector symbols within the visible sheet instead of clipping them below the title block."
        )
        XCTAssertLessThanOrEqual(points.map(\.x).max() ?? 0, 279.4)
    }

    func testSchematicMaterializerShortensGeneratedInternalNetLabelsForReadability() throws {
        let schematic = CircuitIRKiCadSchematicMaterializer().buildDocument(circuitIR: longInternalNetCircuitIR())
        let serialized = try KiCadSchematicWriter().write(schematic)
        let parsed = try KiCadSchematicParser().parse(serialized)

        XCTAssertFalse(
            parsed.labels.filter(\.emitsKiCadConnectivity).contains { $0.text.count > 24 },
            "Generated visual net labels must not overlap symbols with long implementation-derived names: \(parsed.labels.map(\.text))"
        )
        XCTAssertFalse(serialized.contains(#"(label "FILTER1_INTERNAL_CFILT1_RVFILT1""#))
        XCTAssertTrue(
            serialized.contains("NodeMap:FILTER1_INTERNAL_CFILT1_RVFILT1"),
            "The original CircuitIR net name must remain machine-readable as hidden metadata."
        )
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

    private func boardScopedCircuitIR() -> CircuitIR {
        CircuitIR(
            designId: "generic-controller",
            boardId: "low_voltage_control",
            components: [
                CircuitComponent(
                    refdes: "RPU",
                    role: "control pull-up resistor",
                    selectedSymbol: "Device:R",
                    selectedFootprint: "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",
                    manufacturerPartNumber: "example-resistor",
                    sourceEvidence: [SourceEvidence(kind: "design_intent_component", reference: "RPU")],
                    pins: [
                        CircuitPin(componentRefdes: "RPU", pinNumber: "1", canonicalName: "1", electricalType: "passive", symbolPin: "1", footprintPad: "1"),
                        CircuitPin(componentRefdes: "RPU", pinNumber: "2", canonicalName: "2", electricalType: "passive", symbolPin: "2", footprintPad: "2"),
                    ],
                    constraints: [
                        "board_id": "low_voltage_control",
                        "safety_domain": "isolated_secondary",
                        "resistance": "10kOhm",
                    ]
                ),
            ],
            nets: [
                CircuitNet(
                    name: "CTRL_BIAS",
                    role: "isolated low-voltage bias",
                    endpoints: [
                        CircuitNetEndpoint(componentRefdes: "RPU", pinNumber: "1"),
                    ],
                    netClass: "signal",
                    safetyDomain: "isolated_secondary"
                ),
            ],
            constraints: [
                CircuitConstraint(kind: "board_id", target: "low_voltage_control", value: "low_voltage_control"),
                CircuitConstraint(kind: "safety_domain", target: "low_voltage_control", value: "isolated_secondary"),
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

    private func largeConnectorCircuitIR() -> CircuitIR {
        let components = (1...21).map { index in
            CircuitComponent(
                refdes: index == 21 ? "JSPK" : "R\(index)",
                role: index == 21 ? "speaker output connector" : "signal resistor \(index)",
                selectedSymbol: index == 21 ? "Connector_Generic:Conn_01x02" : "Device:R",
                selectedFootprint: index == 21
                    ? "Connector_Audio:Jack_speakON_Neutrik_NL2MDXX-H-3_Horizontal"
                    : "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",
                manufacturerPartNumber: "fixture-\(index)",
                sourceEvidence: [SourceEvidence(kind: "test", reference: "layout")],
                pins: [
                    CircuitPin(componentRefdes: index == 21 ? "JSPK" : "R\(index)", pinNumber: "1", canonicalName: "1", electricalType: "passive", symbolPin: "1", footprintPad: "1"),
                    CircuitPin(componentRefdes: index == 21 ? "JSPK" : "R\(index)", pinNumber: "2", canonicalName: "2", electricalType: "passive", symbolPin: "2", footprintPad: "2"),
                ]
            )
        }
        return CircuitIR(
            designId: "large-layout",
            boardId: "large-layout",
            components: components,
            nets: [],
            constraints: [],
            verificationScenarios: []
        )
    }

    private func longInternalNetCircuitIR() -> CircuitIR {
        CircuitIR(
            designId: "long-net-labels",
            boardId: "long-net-labels",
            components: [
                CircuitComponent(
                    refdes: "CFILT1",
                    role: "filter capacitor",
                    selectedSymbol: "Device:C",
                    selectedFootprint: "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm",
                    manufacturerPartNumber: "fixture-cap",
                    sourceEvidence: [SourceEvidence(kind: "test", reference: "readability")],
                    pins: [
                        CircuitPin(componentRefdes: "CFILT1", pinNumber: "1", canonicalName: "1", electricalType: "passive", symbolPin: "1", footprintPad: "1"),
                        CircuitPin(componentRefdes: "CFILT1", pinNumber: "2", canonicalName: "2", electricalType: "passive", symbolPin: "2", footprintPad: "2"),
                    ]
                ),
                CircuitComponent(
                    refdes: "RVFILT1",
                    role: "filter potentiometer",
                    selectedSymbol: "Device:R_Potentiometer",
                    selectedFootprint: "Potentiometer_THT:Potentiometer_Bourns_3296W_Vertical",
                    manufacturerPartNumber: "fixture-pot",
                    sourceEvidence: [SourceEvidence(kind: "test", reference: "readability")],
                    pins: [
                        CircuitPin(componentRefdes: "RVFILT1", pinNumber: "1", canonicalName: "1", electricalType: "passive", symbolPin: "1", footprintPad: "1"),
                        CircuitPin(componentRefdes: "RVFILT1", pinNumber: "2", canonicalName: "2", electricalType: "passive", symbolPin: "2", footprintPad: "2"),
                    ]
                ),
            ],
            nets: [
                CircuitNet(
                    name: "FILTER1_INTERNAL_CFILT1_RVFILT1",
                    role: "implementation-derived internal filter node",
                    endpoints: [
                        CircuitNetEndpoint(componentRefdes: "CFILT1", pinNumber: "2"),
                        CircuitNetEndpoint(componentRefdes: "RVFILT1", pinNumber: "1"),
                    ],
                    netClass: "signal",
                    safetyDomain: "isolated_secondary"
                ),
            ],
            constraints: [],
            verificationScenarios: []
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

    private func propertyNode(named name: String, value: String, in text: String) -> String? {
        guard let start = text.range(of: #"(property "\#(name)" "\#(value)""#)?.lowerBound else {
            return nil
        }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func point(inPropertyNode node: String) -> KiCadSchematicDocument.Point? {
        guard let regex = try? NSRegularExpression(pattern: #"\(at\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+0\)"#),
              let match = regex.firstMatch(in: node, range: NSRange(node.startIndex..<node.endIndex, in: node)),
              match.numberOfRanges == 3,
              let xRange = Range(match.range(at: 1), in: node),
              let yRange = Range(match.range(at: 2), in: node),
              let x = Double(node[xRange]),
              let y = Double(node[yRange]) else {
            return nil
        }
        return KiCadSchematicDocument.Point(x: x, y: y)
    }
}
