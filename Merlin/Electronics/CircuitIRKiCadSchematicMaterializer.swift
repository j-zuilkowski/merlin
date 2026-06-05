import Foundation

struct CircuitIRSchematicMaterialization: Sendable, Equatable {
    var projectURL: URL
    var schematicURL: URL
    var sourceMap: [String: String]
}

enum CircuitIRKiCadSchematicMaterializerError: Error, Equatable {
    case unresolvedPinGeometry([ElectronicsSchemaIssue])
}

struct CircuitIRKiCadSchematicMaterializer: Sendable {
    private let pinGeometryResolver: KiCadSymbolGeometryResolver

    init(pinGeometryResolver: KiCadSymbolGeometryResolver = KiCadSymbolGeometryResolver()) {
        self.pinGeometryResolver = pinGeometryResolver
    }

    func materialize(
        circuitIR: CircuitIR,
        outputDirectory: URL
    ) throws -> CircuitIRSchematicMaterialization {
        let geometryValidation = validatePinGeometry(circuitIR: circuitIR)
        guard geometryValidation.isValid else {
            throw CircuitIRKiCadSchematicMaterializerError.unresolvedPinGeometry(geometryValidation.issues)
        }

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
            wires: wires(for: circuitIR),
            junctions: junctions(for: circuitIR),
            labels: labels(for: circuitIR),
            sheets: [],
            opaqueNodes: [
                .list([.atom("paper"), .string("A4")]),
                KiCadEmbeddedSymbolLibraryBuilder().libSymbolsNode(for: circuitIR.components.map(\.selectedSymbol)),
                .list([
                    .atom("sheet_instances"),
                    .list([.atom("path"), .string("/"), .list([.atom("page"), .string("1")])]),
                ]),
                .list([.atom("embedded_fonts"), .atom("no")]),
            ]
        )
    }

    func validatePinGeometry(circuitIR: CircuitIR) -> ElectronicsSchemaValidationResult {
        var issues: [ElectronicsSchemaIssue] = []
        for component in circuitIR.components {
            guard let geometry = pinGeometryResolver.resolve(libraryID: component.selectedSymbol) else {
                issues.append(ElectronicsSchemaIssue(
                    code: "PIN_GEOMETRY_UNRESOLVED",
                    message: "\(component.refdes) uses \(component.selectedSymbol), but KiCad pin geometry could not be resolved from installed libraries."
                ))
                continue
            }
            for pin in component.pins where geometry.pin(number: pin.pinNumber, name: pin.symbolPin) == nil
                && geometry.pin(number: pin.pinNumber, name: "") == nil {
                issues.append(ElectronicsSchemaIssue(
                    code: "PIN_GEOMETRY_UNRESOLVED",
                    message: "\(component.refdes).\(pin.pinNumber) \(pin.symbolPin) is not present in \(geometry.libraryID)."
                ))
            }
        }
        return ElectronicsSchemaValidationResult(issues: issues)
    }

    private func symbol(for component: CircuitComponent, index: Int) -> KiCadSchematicDocument.Symbol {
        var properties: [String: String] = [
            "Reference": component.refdes,
            "Value": componentValue(for: component),
            "Role": component.role,
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
        for (key, value) in component.constraints where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            properties["Constraint:\(key)"] = value
        }

        return KiCadSchematicDocument.Symbol(
            uuid: stableUUID("symbol", component.refdes, "\(index)"),
            properties: properties,
            at: symbolPlacement(index: index),
            emitsKiCadSymbol: true
        )
    }

    private func componentValue(for component: CircuitComponent) -> String {
        for key in ["value", "resistance", "capacitance", "inductance", "manufacturer_part_number"] {
            if let value = component.constraints[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        if let manufacturerPartNumber = component.manufacturerPartNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
           !manufacturerPartNumber.isEmpty {
            return manufacturerPartNumber
        }
        return component.role
    }

    private func wires(for circuitIR: CircuitIR) -> [KiCadSchematicDocument.Wire] {
        var wires: [KiCadSchematicDocument.Wire] = []
        var seen = Set<String>()
        for net in circuitIR.nets {
            let points = uniquePoints(net.endpoints.compactMap { endpoint in
                pinPoint(for: endpoint, circuitIR: circuitIR)
            })
            guard let first = points.first, points.count > 1 else { continue }
            for point in points.dropFirst() where first != point {
                let key = wireKey(first, point)
                guard seen.insert(key).inserted else { continue }
                wires.append(KiCadSchematicDocument.Wire(start: first, end: point))
            }
        }
        return wires
    }

    private func labels(for circuitIR: CircuitIR) -> [KiCadSchematicDocument.Label] {
        let pointDegrees = wireEndpointDegrees(for: circuitIR)
        return circuitIR.nets.flatMap { net -> [KiCadSchematicDocument.Label] in
            let labels = net.endpoints.compactMap { endpoint -> KiCadSchematicDocument.Label? in
                guard let at = pinPoint(for: endpoint, circuitIR: circuitIR) else { return nil }
                guard (pointDegrees[pointKey(at)] ?? 0) <= 1 else { return nil }
                return KiCadSchematicDocument.Label(kind: .local, text: net.name, emitsKiCadConnectivity: true, at: at)
            }
            if labels.isEmpty {
                return [KiCadSchematicDocument.Label(kind: .local, text: net.name, emitsKiCadConnectivity: false)]
            }
            return labels
        }
    }

    private func pinPoint(
        for endpoint: CircuitNetEndpoint,
        circuitIR: CircuitIR
    ) -> KiCadSchematicDocument.Point? {
        guard let index = circuitIR.components.firstIndex(where: { $0.refdes == endpoint.componentRefdes }) else {
            return nil
        }
        let component = circuitIR.components[index]
        let origin = symbolPlacement(index: index)
        guard let pin = component.pins.first(where: { $0.pinNumber == endpoint.pinNumber }),
              let offset = pinOffset(component: component, pin: pin) else {
            return nil
        }
        return KiCadSchematicDocument.Point(x: origin.x + offset.x, y: origin.y - offset.y)
    }

    private func symbolPlacement(index: Int) -> KiCadSchematicDocument.Point {
        let column = index % 4
        let row = index / 4
        return KiCadSchematicDocument.Point(
            x: 25.4 + Double(column) * 50.8,
            y: 25.4 + Double(row) * 38.1
        )
    }

    private func pinOffset(component: CircuitComponent, pin: CircuitPin) -> KiCadSchematicDocument.Point? {
        guard let geometry = pinGeometryResolver.resolve(libraryID: component.selectedSymbol) else {
            return nil
        }
        return geometry.pin(number: pin.pinNumber, name: pin.symbolPin)?.at
            ?? geometry.pin(number: pin.pinNumber, name: "")?.at
    }

    private func junctions(for circuitIR: CircuitIR) -> [KiCadSchematicDocument.Junction] {
        circuitIR.nets.compactMap { net in
            let points = uniquePoints(net.endpoints.compactMap { endpoint in
                pinPoint(for: endpoint, circuitIR: circuitIR)
            })
            guard points.count > 2, let first = points.first else { return nil }
            return KiCadSchematicDocument.Junction(at: first)
        }
    }

    private func wireEndpointDegrees(for circuitIR: CircuitIR) -> [String: Int] {
        var degrees: [String: Int] = [:]
        for wire in wires(for: circuitIR) {
            degrees[pointKey(wire.start), default: 0] += 1
            degrees[pointKey(wire.end), default: 0] += 1
        }
        return degrees
    }

    private func uniquePoints(_ points: [KiCadSchematicDocument.Point]) -> [KiCadSchematicDocument.Point] {
        var seen = Set<String>()
        var result: [KiCadSchematicDocument.Point] = []
        for point in points {
            guard seen.insert(pointKey(point)).inserted else { continue }
            result.append(point)
        }
        return result
    }

    private func wireKey(_ a: KiCadSchematicDocument.Point, _ b: KiCadSchematicDocument.Point) -> String {
        [pointKey(a), pointKey(b)].sorted().joined(separator: "|")
    }

    private func pointKey(_ point: KiCadSchematicDocument.Point) -> String {
        "\(roundedKey(point.x)),\(roundedKey(point.y))"
    }

    private func roundedKey(_ value: Double) -> String {
        String(format: "%.4f", value)
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
