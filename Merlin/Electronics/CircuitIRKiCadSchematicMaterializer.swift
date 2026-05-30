import Foundation

struct CircuitIRSchematicMaterialization: Sendable, Equatable {
    var projectURL: URL
    var schematicURL: URL
    var sourceMap: [String: String]
}

struct CircuitIRKiCadSchematicMaterializer: Sendable {
    func materialize(
        circuitIR: CircuitIR,
        outputDirectory: URL
    ) throws -> CircuitIRSchematicMaterialization {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let projectURL = outputDirectory.appendingPathComponent("\(circuitIR.boardId).kicad_pro")
        let schematicURL = outputDirectory.appendingPathComponent("\(circuitIR.boardId).kicad_sch")
        let projectData = try JSONEncoder.merlinElectronics.encode(KiCadProjectManifest(
            designId: circuitIR.designId,
            boardId: circuitIR.boardId,
            schematicFile: schematicURL.lastPathComponent,
            generator: "merlin-electronics"
        ))

        let document = buildDocument(circuitIR: circuitIR)
        let schematicText = try KiCadSchematicWriter().write(document)

        try projectData.write(to: projectURL, options: .atomic)
        try schematicText.write(to: schematicURL, atomically: true, encoding: .utf8)

        return CircuitIRSchematicMaterialization(
            projectURL: projectURL,
            schematicURL: schematicURL,
            sourceMap: sourceMap(for: circuitIR)
        )
    }

    func buildDocument(circuitIR: CircuitIR) -> KiCadSchematicDocument {
        KiCadSchematicDocument(
            version: 20250114,
            generator: "merlin-electronics",
            uuid: stableUUID("root", circuitIR.designId, circuitIR.boardId),
            symbols: circuitIR.components.enumerated().map { index, component in
                symbol(for: component, index: index)
            },
            wires: [],
            junctions: [],
            labels: circuitIR.nets.map { net in
                KiCadSchematicDocument.Label(kind: .local, text: net.name, emitsKiCadConnectivity: false)
            },
            sheets: [],
            opaqueNodes: [
                .list([.atom("paper"), .string("A4")]),
                .list([.atom("lib_symbols")]),
                .list([
                    .atom("sheet_instances"),
                    .list([.atom("path"), .string("/"), .list([.atom("page"), .string("1")])]),
                ]),
                .list([.atom("embedded_fonts"), .atom("no")]),
            ]
        )
    }

    private func symbol(for component: CircuitComponent, index: Int) -> KiCadSchematicDocument.Symbol {
        var properties: [String: String] = [
            "Reference": component.refdes,
            "Value": component.role,
            "Symbol": component.selectedSymbol,
            "Source": "circuit-component:\(component.refdes)",
            "Pins": component.pins
                .sorted { $0.pinNumber.localizedStandardCompare($1.pinNumber) == .orderedAscending }
                .map { "\($0.pinNumber):\($0.symbolPin):\($0.canonicalName)" }
                .joined(separator: ","),
        ]

        if let footprint = component.selectedFootprint,
           !footprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            properties["Footprint"] = footprint
        }
        if let manufacturerPartNumber = component.manufacturerPartNumber,
           !manufacturerPartNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            properties["ManufacturerPartNumber"] = manufacturerPartNumber
        }
        if !component.sourceEvidence.isEmpty {
            properties["SourceEvidence"] = component.sourceEvidence
                .map { "\($0.kind):\($0.reference)" }
                .joined(separator: "; ")
        }

        return KiCadSchematicDocument.Symbol(
            uuid: stableUUID("symbol", component.refdes, "\(index)"),
            properties: properties,
            emitsKiCadSymbol: false
        )
    }

    private func wires(for circuitIR: CircuitIR) -> [KiCadSchematicDocument.Wire] {
        var wires: [KiCadSchematicDocument.Wire] = []
        for (index, net) in circuitIR.nets.enumerated() where net.endpoints.count > 1 {
            let y = Double(20 + (index * 10))
            wires.append(KiCadSchematicDocument.Wire(
                start: .init(x: 10, y: y),
                end: .init(x: 10 + Double(net.endpoints.count * 10), y: y)
            ))
        }
        return wires
    }

    private func junctions(for circuitIR: CircuitIR) -> [KiCadSchematicDocument.Junction] {
        circuitIR.nets.enumerated().compactMap { index, net in
            guard net.endpoints.count > 2 else { return nil }
            return KiCadSchematicDocument.Junction(at: .init(x: 20, y: Double(20 + (index * 10))))
        }
    }

    private func sourceMap(for circuitIR: CircuitIR) -> [String: String] {
        var map: [String: String] = [:]
        for component in circuitIR.components {
            map[component.refdes] = "circuit-component:\(component.refdes)"
        }
        for net in circuitIR.nets {
            map["net:\(net.name)"] = "circuit-net:\(net.name)"
        }
        return map
    }

    private func stableUUID(_ parts: String...) -> String {
        let input = parts.joined(separator: "|")
        let hash = input.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

struct CircuitIRSchematicParityChecker: Sendable {
    func check(
        circuitIR: CircuitIR,
        schematic: KiCadSchematicDocument
    ) -> ElectronicsSchemaValidationResult {
        var issues: [ElectronicsSchemaIssue] = []
        let symbolsByReference = Dictionary(
            uniqueKeysWithValues: schematic.symbols.compactMap { symbol -> (String, KiCadSchematicDocument.Symbol)? in
                guard let reference = symbol.property(named: "Reference") else { return nil }
                return (reference, symbol)
            }
        )
        let labels = Set(schematic.labels.map(\.text))

        for component in circuitIR.components {
            guard let symbol = symbolsByReference[component.refdes] else {
                issues.append(issue(
                    "SCHEMATIC_COMPONENT_MISSING",
                    "Schematic is missing component \(component.refdes)."
                ))
                continue
            }
            if symbol.property(named: "Symbol") != component.selectedSymbol {
                issues.append(issue(
                    "SCHEMATIC_SYMBOL_MISMATCH",
                    "Schematic symbol for \(component.refdes) does not match Circuit IR."
                ))
            }
            if let footprint = component.selectedFootprint,
               symbol.property(named: "Footprint") != footprint {
                issues.append(issue(
                    "SCHEMATIC_FOOTPRINT_MISMATCH",
                    "Schematic footprint for \(component.refdes) does not match Circuit IR."
                ))
            }
        }

        for net in circuitIR.nets where !labels.contains(net.name) {
            issues.append(issue(
                "SCHEMATIC_NET_MISSING",
                "Schematic is missing net label \(net.name)."
            ))
        }

        return ElectronicsSchemaValidationResult(issues: issues)
    }

    private func issue(_ code: String, _ message: String) -> ElectronicsSchemaIssue {
        ElectronicsSchemaIssue(code: code, message: message)
    }
}

private struct KiCadProjectManifest: Codable {
    var designId: String
    var boardId: String
    var schematicFile: String
    var generator: String

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case boardId = "board_id"
        case schematicFile = "schematic_file"
        case generator
    }
}

private extension JSONEncoder {
    static var merlinElectronics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
