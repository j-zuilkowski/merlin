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
        if let boardID = component.constraints["board_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !boardID.isEmpty {
            properties["BoardID"] = boardID
        }
        if let safetyDomain = component.constraints["safety_domain"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !safetyDomain.isEmpty {
            properties["SafetyDomain"] = safetyDomain
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
            for endpoint in net.endpoints {
                guard let stub = endpointStub(for: endpoint, circuitIR: circuitIR) else { continue }
                let key = wireKey(stub.pinPoint, stub.labelPoint)
                guard seen.insert(key).inserted else { continue }
                wires.append(KiCadSchematicDocument.Wire(start: stub.pinPoint, end: stub.labelPoint))
            }
        }
        return wires
    }

    private func labels(for circuitIR: CircuitIR) -> [KiCadSchematicDocument.Label] {
        return circuitIR.nets.enumerated().flatMap { netIndex, net -> [KiCadSchematicDocument.Label] in
            let visibleName = visibleNetName(for: net.name, index: netIndex)
            let labels = net.endpoints.compactMap { endpoint -> KiCadSchematicDocument.Label? in
                guard let stub = endpointStub(for: endpoint, circuitIR: circuitIR) else { return nil }
                return KiCadSchematicDocument.Label(kind: .local, text: visibleName, emitsKiCadConnectivity: true, at: stub.labelPoint)
            }
            let metadataLabels = netMetadataLabels(originalName: net.name, visibleName: visibleName)
            if labels.isEmpty {
                return [KiCadSchematicDocument.Label(kind: .local, text: visibleName, emitsKiCadConnectivity: false)]
                    + metadataLabels
            }
            return labels + metadataLabels
        }
    }

    private func visibleNetName(for name: String, index: Int) -> String {
        if name.count <= 24 {
            return name
        }
        return "N\(index + 1)"
    }

    private func netMetadataLabels(originalName: String, visibleName: String) -> [KiCadSchematicDocument.Label] {
        guard originalName != visibleName else { return [] }
        return [
            KiCadSchematicDocument.Label(kind: .local, text: originalName, emitsKiCadConnectivity: false),
            KiCadSchematicDocument.Label(kind: .local, text: "NodeMap:\(originalName)=\(visibleName)", emitsKiCadConnectivity: false),
        ]
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
        let column = index % 6
        let row = index / 6
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
        []
    }

    private struct EndpointStub {
        var pinPoint: KiCadSchematicDocument.Point
        var labelPoint: KiCadSchematicDocument.Point
    }

    private func endpointStub(
        for endpoint: CircuitNetEndpoint,
        circuitIR: CircuitIR
    ) -> EndpointStub? {
        guard let index = circuitIR.components.firstIndex(where: { $0.refdes == endpoint.componentRefdes }) else {
            return nil
        }
        let component = circuitIR.components[index]
        guard let pin = component.pins.first(where: { $0.pinNumber == endpoint.pinNumber }),
              let offset = pinOffset(component: component, pin: pin),
              let pinPoint = pinPoint(for: endpoint, circuitIR: circuitIR) else {
            return nil
        }
        let horizontalDirection = offset.x < 0 ? -1.0 : 1.0
        let labelPoint = KiCadSchematicDocument.Point(
            x: pinPoint.x + horizontalDirection * 5.08,
            y: pinPoint.y
        )
        return EndpointStub(pinPoint: pinPoint, labelPoint: labelPoint)
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
            schematic.symbols.compactMap { symbol -> (String, KiCadSchematicDocument.Symbol)? in
                guard symbol.emitsKiCadSymbol else { return nil }
                guard let reference = symbol.property(named: "Reference") else { return nil }
                return (reference, symbol)
            },
            uniquingKeysWith: { first, _ in first }
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

struct SchematicRealismValidator: Sendable {
    private let currentKiCadSchematicVersion = 20250114

    func validate(
        circuitIR: CircuitIR,
        schematic: KiCadSchematicDocument
    ) -> ElectronicsSchemaValidationResult {
        var issues: [ElectronicsSchemaIssue] = []

        if schematic.version < currentKiCadSchematicVersion {
            issues.append(issue(
                "SCHEMATIC_KICAD_VERSION_STALE",
                "Schematic uses KiCad format \(schematic.version); expected \(currentKiCadSchematicVersion) or newer."
            ))
        }

        if schematic.generator != "merlin-electronics" {
            issues.append(issue(
                "SCHEMATIC_GENERATOR_MISMATCH",
                "Schematic generator must be merlin-electronics, got \(schematic.generator)."
            ))
        }

        let emittedSymbols = schematic.symbols.filter(\.emitsKiCadSymbol)
        let emittedSymbolsByReference = Dictionary(
            emittedSymbols.compactMap { symbol -> (String, KiCadSchematicDocument.Symbol)? in
                guard let reference = symbol.property(named: "Reference") else { return nil }
                return (reference, symbol)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for symbol in schematic.symbols where !symbol.emitsKiCadSymbol || isCompositeSymbol(symbol) {
            issues.append(issue(
                "SCHEMATIC_COMPOSITE_BLOCK",
                "Schematic contains non-emitted or composite block symbol \(symbol.property(named: "Reference") ?? "<unknown>")."
            ))
        }

        for component in circuitIR.components {
            if isCompositeComponent(component) {
                issues.append(issue(
                    "SCHEMATIC_COMPOSITE_BLOCK",
                    "\(component.refdes) is a composite functional block, not a discrete schematic component."
                ))
            }

            guard let symbol = emittedSymbolsByReference[component.refdes] else {
                issues.append(issue(
                    "SCHEMATIC_COMPONENT_MISSING",
                    "Schematic is missing emitted KiCad symbol for \(component.refdes)."
                ))
                continue
            }

            if symbol.property(named: "Symbol") != component.selectedSymbol {
                issues.append(issue(
                    "SCHEMATIC_SYMBOL_MISMATCH",
                    "Schematic symbol for \(component.refdes) does not match Circuit IR selected symbol."
                ))
            }

            if let footprint = component.selectedFootprint,
               !footprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               symbol.property(named: "Footprint") != footprint {
                issues.append(issue(
                    "SCHEMATIC_FOOTPRINT_MISMATCH",
                    "Schematic footprint for \(component.refdes) does not match Circuit IR."
                ))
            }

            if symbol.property(named: "Source") != "circuit-component:\(component.refdes)" {
                issues.append(issue(
                    "SCHEMATIC_SOURCE_MISSING",
                    "Schematic symbol \(component.refdes) is not traceable to its Circuit IR component."
                ))
            }

            if !component.sourceEvidence.isEmpty,
               (symbol.property(named: "SourceEvidence")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                issues.append(issue(
                    "SCHEMATIC_SOURCE_EVIDENCE_MISSING",
                    "Schematic symbol \(component.refdes) is missing source evidence."
                ))
            }

            let emittedPinNumbers = pinNumbers(from: symbol)
            for pin in component.pins where !emittedPinNumbers.contains(pin.pinNumber) {
                issues.append(issue(
                    "SCHEMATIC_PIN_MISSING",
                    "Schematic symbol \(component.refdes) is missing pin \(pin.pinNumber)."
                ))
            }
        }

        let emittedConnectivityLabels = Set(schematic.labels.filter(\.emitsKiCadConnectivity).map(\.text))
        let metadataLabels = Set(schematic.labels.filter { !$0.emitsKiCadConnectivity }.map(\.text))
        for (netIndex, net) in circuitIR.nets.enumerated() {
            let visibleName = visibleNetName(for: net.name, index: netIndex)
            let hasVisibleConnectivity = emittedConnectivityLabels.contains(net.name)
                || emittedConnectivityLabels.contains(visibleName)
            let hasOriginalEvidence = visibleName == net.name
                || (metadataLabels.contains(net.name) && metadataLabels.contains("NodeMap:\(net.name)=\(visibleName)"))
            if !hasVisibleConnectivity || !hasOriginalEvidence {
                issues.append(issue(
                    "SCHEMATIC_NET_CONNECTIVITY_MISSING",
                    "Schematic net \(net.name) is missing emitted KiCad connectivity or hidden original-name evidence."
                ))
            }
        }

        return ElectronicsSchemaValidationResult(issues: issues)
    }

    private func visibleNetName(for name: String, index: Int) -> String {
        if name.count <= 24 {
            return name
        }
        return "N\(index + 1)"
    }

    private func pinNumbers(from symbol: KiCadSchematicDocument.Symbol) -> Set<String> {
        guard let pins = symbol.property(named: "Pins") else { return [] }
        return Set(pins.split(separator: ",").compactMap { entry in
            entry.split(separator: ":").first.map(String.init)
        })
    }

    private func isCompositeComponent(_ component: CircuitComponent) -> Bool {
        let haystack = [
            component.refdes,
            component.role,
            component.selectedSymbol,
            component.manufacturerPartNumber ?? "",
        ].joined(separator: " ").lowercased()

        return haystack.contains("functional block")
            || haystack.contains("composite")
            || haystack.contains("complete amplifier")
            || haystack.contains("amplifier block")
            || haystack.contains("placeholder")
    }

    private func isCompositeSymbol(_ symbol: KiCadSchematicDocument.Symbol) -> Bool {
        let haystack = [
            symbol.property(named: "Reference") ?? "",
            symbol.property(named: "Symbol") ?? "",
            symbol.property(named: "Role") ?? "",
            symbol.property(named: "Source") ?? "",
        ].joined(separator: " ").lowercased()

        return haystack.contains("functional block")
            || haystack.contains("composite")
            || haystack.contains("complete amplifier")
            || haystack.contains("amplifierblock")
            || haystack.contains("amplifier block")
            || haystack.contains("placeholder")
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
