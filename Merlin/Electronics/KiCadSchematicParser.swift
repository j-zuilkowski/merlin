import Foundation

enum KiCadSExpression: Equatable, Sendable {
    case list([KiCadSExpression])
    case atom(String)
    case string(String)
}

struct KiCadSchematicDocument: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    struct Symbol: Equatable, Sendable {
        var uuid: String?
        var properties: [String: String]
        var at: Point? = nil
        var emitsKiCadSymbol: Bool = true

        func property(named name: String) -> String? {
            properties[name]
        }
    }

    struct Wire: Equatable, Sendable {
        var start: Point
        var end: Point
    }

    struct Junction: Equatable, Sendable {
        var at: Point
    }

    struct Label: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case local
            case global
            case hierarchical
        }

        var kind: Kind
        var text: String
        var emitsKiCadConnectivity: Bool = true
        var at: Point? = nil
    }

    struct SheetPin: Equatable, Sendable {
        var name: String
        var kind: String
    }

    struct Sheet: Equatable, Sendable {
        var uuid: String?
        var name: String
        var file: String
        var pins: [SheetPin]
    }

    var version: Int
    var generator: String
    var uuid: String
    var symbols: [Symbol]
    var wires: [Wire]
    var junctions: [Junction]
    var labels: [Label]
    var sheets: [Sheet]
    var opaqueNodes: [KiCadSExpression]
}

enum KiCadSchematicParserError: Error, Equatable {
    case malformed(String)
    case unsupported(String)
}

struct KiCadSchematicParser {
    func parse(_ input: String) throws -> KiCadSchematicDocument {
        let tokens = try tokenize(input)
        var cursor = 0
        let root = try parseExpression(tokens, &cursor)
        guard cursor == tokens.count else {
            throw KiCadSchematicParserError.malformed("Trailing tokens after root expression")
        }

        guard case .list(let rootNodes) = root,
              rootNodes.first == .atom("kicad_sch") else {
            throw KiCadSchematicParserError.unsupported("Root node must be (kicad_sch ...)")
        }

        var version = 0
        var generator = ""
        var uuid = ""
        var symbols: [KiCadSchematicDocument.Symbol] = []
        var wires: [KiCadSchematicDocument.Wire] = []
        var junctions: [KiCadSchematicDocument.Junction] = []
        var labels: [KiCadSchematicDocument.Label] = []
        var sheets: [KiCadSchematicDocument.Sheet] = []
        var opaqueNodes: [KiCadSExpression] = []

        for node in rootNodes.dropFirst() {
            guard case .list(let list) = node,
                  let head = list.first?.atomValue else {
                opaqueNodes.append(node)
                continue
            }

            switch head {
            case "version":
                guard let atom = list.dropFirst().first?.atomValue,
                      let parsed = Int(atom) else {
                    throw KiCadSchematicParserError.malformed("Invalid version node")
                }
                version = parsed

            case "generator":
                guard let value = list.dropFirst().first?.stringOrAtomValue else {
                    throw KiCadSchematicParserError.malformed("Invalid generator node")
                }
                generator = value

            case "uuid":
                guard let value = list.dropFirst().first?.stringOrAtomValue else {
                    throw KiCadSchematicParserError.malformed("Invalid uuid node")
                }
                uuid = value

            case "symbol":
                symbols.append(try parseSymbol(node))

            case "text":
                if let metadata = try parseMerlinMetadataText(node) {
                    switch metadata {
                    case .component(let symbol):
                        symbols.append(symbol)
                    case .net(let label):
                        labels.append(label)
                    }
                } else {
                    opaqueNodes.append(node)
                }

            case "wire":
                wires.append(try parseWire(node))

            case "junction":
                junctions.append(try parseJunction(node))

            case "label", "global_label", "hierarchical_label":
                labels.append(try parseLabel(node, head: head))

            case "sheet":
                sheets.append(try parseSheet(node))

            default:
                opaqueNodes.append(node)
            }
        }

        return KiCadSchematicDocument(
            version: version,
            generator: generator,
            uuid: uuid,
            symbols: symbols,
            wires: wires,
            junctions: junctions,
            labels: labels,
            sheets: sheets,
            opaqueNodes: opaqueNodes
        )
    }

    func parseFragment(_ input: String) throws -> KiCadSExpression {
        let tokens = try tokenize(input)
        var cursor = 0
        let expression = try parseExpression(tokens, &cursor)
        guard cursor == tokens.count else {
            throw KiCadSchematicParserError.malformed("Trailing tokens after expression fragment")
        }
        return expression
    }

    private func parseSymbol(_ expression: KiCadSExpression) throws -> KiCadSchematicDocument.Symbol {
        guard case .list(let list) = expression else {
            throw KiCadSchematicParserError.malformed("symbol must be a list")
        }

        var uuid: String?
        var properties: [String: String] = [:]
        var at: KiCadSchematicDocument.Point?

        for item in list.dropFirst() {
            guard case .list(let child) = item,
                  let head = child.first?.atomValue else {
                continue
            }

            if head == "uuid", let value = child.dropFirst().first?.stringOrAtomValue {
                uuid = value
            }

            if head == "at",
               child.count >= 3,
               let x = child[1].doubleValue,
               let y = child[2].doubleValue {
                at = KiCadSchematicDocument.Point(x: x, y: y)
            }

            if head == "property",
               child.count >= 3,
               let key = child[1].stringOrAtomValue,
               let value = child[2].stringOrAtomValue {
                properties[key] = value
            }
        }

        return KiCadSchematicDocument.Symbol(uuid: uuid, properties: properties, at: at, emitsKiCadSymbol: true)
    }

    private func parseWire(_ expression: KiCadSExpression) throws -> KiCadSchematicDocument.Wire {
        guard case .list(let list) = expression else {
            throw KiCadSchematicParserError.malformed("wire must be a list")
        }

        for item in list.dropFirst() {
            guard case .list(let child) = item,
                  child.first == .atom("pts") else {
                continue
            }

            let points = try child.dropFirst().map(parseXY)
            guard points.count >= 2 else {
                throw KiCadSchematicParserError.malformed("wire requires two points")
            }
            return KiCadSchematicDocument.Wire(start: points[0], end: points[1])
        }

        throw KiCadSchematicParserError.malformed("wire missing pts")
    }

    private func parseJunction(_ expression: KiCadSExpression) throws -> KiCadSchematicDocument.Junction {
        guard case .list(let list) = expression else {
            throw KiCadSchematicParserError.malformed("junction must be a list")
        }

        for item in list.dropFirst() {
            guard case .list(let child) = item,
                  child.first == .atom("at"),
                  child.count >= 3,
                  let x = child[1].doubleValue,
                  let y = child[2].doubleValue else {
                continue
            }
            return KiCadSchematicDocument.Junction(at: .init(x: x, y: y))
        }

        throw KiCadSchematicParserError.malformed("junction missing at")
    }

    private func parseLabel(_ expression: KiCadSExpression, head: String) throws -> KiCadSchematicDocument.Label {
        guard case .list(let list) = expression,
              let text = list.dropFirst().first?.stringOrAtomValue else {
            throw KiCadSchematicParserError.malformed("label missing text")
        }

        let kind: KiCadSchematicDocument.Label.Kind
        switch head {
        case "label":
            kind = .local
        case "global_label":
            kind = .global
        case "hierarchical_label":
            kind = .hierarchical
        default:
            throw KiCadSchematicParserError.unsupported("Unsupported label type: \(head)")
        }

        let at = list.compactMap { item -> KiCadSchematicDocument.Point? in
            guard case .list(let child) = item,
                  child.first == .atom("at"),
                  child.count >= 3,
                  let x = child[1].doubleValue,
                  let y = child[2].doubleValue else {
                return nil
            }
            return KiCadSchematicDocument.Point(x: x, y: y)
        }.first

        return KiCadSchematicDocument.Label(kind: kind, text: text, emitsKiCadConnectivity: true, at: at)
    }

    private func parseSheet(_ expression: KiCadSExpression) throws -> KiCadSchematicDocument.Sheet {
        guard case .list(let list) = expression else {
            throw KiCadSchematicParserError.malformed("sheet must be a list")
        }

        var uuid: String?
        var name = ""
        var file = ""
        var pins: [KiCadSchematicDocument.SheetPin] = []

        for item in list.dropFirst() {
            guard case .list(let child) = item,
                  let head = child.first?.atomValue else {
                continue
            }

            switch head {
            case "uuid":
                uuid = child.dropFirst().first?.stringOrAtomValue
            case "name":
                name = child.dropFirst().first?.stringOrAtomValue ?? ""
            case "file":
                file = child.dropFirst().first?.stringOrAtomValue ?? ""
            case "pin":
                if child.count >= 3,
                   let pinName = child[1].stringOrAtomValue,
                   let pinKind = child[2].stringOrAtomValue {
                    pins.append(.init(name: pinName, kind: pinKind))
                }
            default:
                break
            }
        }

        return KiCadSchematicDocument.Sheet(uuid: uuid, name: name, file: file, pins: pins)
    }

    private enum MerlinMetadataText {
        case component(KiCadSchematicDocument.Symbol)
        case net(KiCadSchematicDocument.Label)
    }

    private func parseMerlinMetadataText(_ expression: KiCadSExpression) throws -> MerlinMetadataText? {
        guard case .list(let list) = expression,
              let text = list.dropFirst().first?.stringOrAtomValue else {
            return nil
        }

        if text.hasPrefix("MERLIN_NET:") {
            let name = String(text.dropFirst("MERLIN_NET:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw KiCadSchematicParserError.malformed("MERLIN_NET metadata missing net name")
            }
            return .net(KiCadSchematicDocument.Label(kind: .local, text: name, emitsKiCadConnectivity: false, at: nil))
        }

        if text.hasPrefix("MERLIN_COMPONENT:") {
            let jsonText = String(text.dropFirst("MERLIN_COMPONENT:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = jsonText.data(using: .utf8),
                  let properties = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                throw KiCadSchematicParserError.malformed("MERLIN_COMPONENT metadata must contain a string dictionary")
            }
            return .component(KiCadSchematicDocument.Symbol(uuid: nil, properties: properties, emitsKiCadSymbol: false))
        }

        return nil
    }

    private func parseXY(_ expression: KiCadSExpression) throws -> KiCadSchematicDocument.Point {
        guard case .list(let list) = expression,
              list.first == .atom("xy"),
              list.count >= 3,
              let x = list[1].doubleValue,
              let y = list[2].doubleValue else {
            throw KiCadSchematicParserError.malformed("Expected (xy <x> <y>)")
        }
        return .init(x: x, y: y)
    }

    private enum Token: Equatable {
        case lparen
        case rparen
        case atom(String)
        case string(String)
    }

    private func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        var index = input.startIndex

        func advance() {
            index = input.index(after: index)
        }

        while index < input.endIndex {
            let char = input[index]
            if char.isWhitespace {
                advance()
                continue
            }
            if char == "(" {
                tokens.append(.lparen)
                advance()
                continue
            }
            if char == ")" {
                tokens.append(.rparen)
                advance()
                continue
            }
            if char == "\"" {
                advance()
                var value = ""
                var closed = false
                while index < input.endIndex {
                    let c = input[index]
                    if c == "\\" {
                        let next = input.index(after: index)
                        guard next < input.endIndex else {
                            throw KiCadSchematicParserError.malformed("Dangling escape in string")
                        }
                        value.append(input[next])
                        index = input.index(after: next)
                        continue
                    }
                    if c == "\"" {
                        closed = true
                        advance()
                        break
                    }
                    value.append(c)
                    advance()
                }
                guard closed else {
                    throw KiCadSchematicParserError.malformed("Unterminated string")
                }
                tokens.append(.string(value))
                continue
            }

            var atom = ""
            while index < input.endIndex {
                let c = input[index]
                if c.isWhitespace || c == "(" || c == ")" {
                    break
                }
                atom.append(c)
                advance()
            }
            if atom.isEmpty {
                throw KiCadSchematicParserError.malformed("Invalid token")
            }
            tokens.append(.atom(atom))
        }

        return tokens
    }

    private func parseExpression(_ tokens: [Token], _ cursor: inout Int) throws -> KiCadSExpression {
        guard cursor < tokens.count else {
            throw KiCadSchematicParserError.malformed("Unexpected end of input")
        }

        switch tokens[cursor] {
        case .atom(let value):
            cursor += 1
            return .atom(value)
        case .string(let value):
            cursor += 1
            return .string(value)
        case .lparen:
            cursor += 1
            var list: [KiCadSExpression] = []
            while cursor < tokens.count && tokens[cursor] != .rparen {
                list.append(try parseExpression(tokens, &cursor))
            }
            guard cursor < tokens.count, tokens[cursor] == .rparen else {
                throw KiCadSchematicParserError.malformed("Unclosed list")
            }
            cursor += 1
            return .list(list)
        case .rparen:
            throw KiCadSchematicParserError.malformed("Unexpected closing paren")
        }
    }
}

struct KiCadSchematicWriter {
    func write(_ document: KiCadSchematicDocument) throws -> String {
        var nodes: [KiCadSExpression] = [
            .atom("kicad_sch"),
            .list([.atom("version"), .atom(String(document.version))]),
            .list([.atom("generator"), .string(document.generator)]),
            .list([.atom("uuid"), .string(document.uuid)]),
        ]
        var metadataTextIndex = 0
        let frontOpaqueHeads: Set<String> = ["paper", "title_block", "lib_symbols"]
        let frontOpaqueNodes = document.opaqueNodes.filter { node in
            node.listHead.map(frontOpaqueHeads.contains) ?? false
        }
        let trailingOpaqueNodes = document.opaqueNodes.filter { node in
            !(node.listHead.map(frontOpaqueHeads.contains) ?? false)
        }
        nodes.append(contentsOf: frontOpaqueNodes)

        for symbol in document.symbols {
            if !symbol.emitsKiCadSymbol {
                nodes.append(metadataTextNode(text: merlinComponentMetadata(for: symbol), index: metadataTextIndex))
                metadataTextIndex += 1
                continue
            }
            let reference = symbol.properties["Reference"] ?? "U?"
            let libID = KiCadLibraryIDCanonicalizer.canonical(symbol.properties["Symbol"] ?? "Device:R")
            let at = symbol.at ?? symbolPlacement(index: metadataTextIndex)
            var symbolNodes: [KiCadSExpression] = [.atom("symbol")]
            symbolNodes.append(.list([.atom("lib_id"), .string(libID)]))
            symbolNodes.append(.list([.atom("at"), .atom(numberString(at.x)), .atom(numberString(at.y)), .atom("0")]))
            symbolNodes.append(.list([.atom("unit"), .atom("1")]))
            symbolNodes.append(.list([.atom("exclude_from_sim"), .atom("no")]))
            symbolNodes.append(.list([.atom("in_bom"), .atom("yes")]))
            symbolNodes.append(.list([.atom("on_board"), .atom("yes")]))
            symbolNodes.append(.list([.atom("dnp"), .atom("no")]))
            if let uuid = symbol.uuid {
                symbolNodes.append(.list([.atom("uuid"), .string(uuid)]))
            }
            for (propertyIndex, key) in symbol.properties.keys.sorted().enumerated() {
                if let value = symbol.properties[key] {
                    symbolNodes.append(propertyNode(
                        key: key,
                        value: value,
                        at: KiCadSchematicDocument.Point(x: at.x, y: at.y + Double(propertyIndex + 1) * 1.27),
                        hidden: hiddenPropertyNames.contains(key) || key.hasPrefix("Constraint:")
                    ))
                }
            }
            for pinNumber in pinNumbers(for: symbol) {
                symbolNodes.append(.list([
                    .atom("pin"),
                    .string(pinNumber),
                    .list([.atom("uuid"), .string(stableTextUUID("pin", reference, pinNumber))]),
                ]))
            }
            symbolNodes.append(.list([
                .atom("instances"),
                .list([
                    .atom("project"),
                    .string("merlin"),
                    .list([
                        .atom("path"),
                        .string("/"),
                        .list([.atom("reference"), .string(reference)]),
                        .list([.atom("unit"), .atom("1")]),
                    ]),
                ]),
            ]))
            nodes.append(.list(symbolNodes))
            metadataTextIndex += 1
        }

        for wire in document.wires {
            nodes.append(.list([
                .atom("wire"),
                .list([
                    .atom("pts"),
                    .list([.atom("xy"), .atom(numberString(wire.start.x)), .atom(numberString(wire.start.y))]),
                    .list([.atom("xy"), .atom(numberString(wire.end.x)), .atom(numberString(wire.end.y))]),
                ]),
                .list([
                    .atom("stroke"),
                    .list([.atom("width"), .atom("0")]),
                    .list([.atom("type"), .atom("default")]),
                ]),
                .list([.atom("uuid"), .string(stableTextUUID("wire", numberString(wire.start.x), numberString(wire.start.y), numberString(wire.end.x), numberString(wire.end.y)))]),
            ]))
        }

        for junction in document.junctions {
            nodes.append(.list([
                .atom("junction"),
                .list([.atom("at"), .atom(numberString(junction.at.x)), .atom(numberString(junction.at.y))]),
                .list([.atom("diameter"), .atom("0")]),
                .list([.atom("color"), .atom("0"), .atom("0"), .atom("0"), .atom("0")]),
                .list([.atom("uuid"), .string(stableTextUUID("junction", numberString(junction.at.x), numberString(junction.at.y)))]),
            ]))
        }

        for label in document.labels {
            if !label.emitsKiCadConnectivity {
                nodes.append(metadataTextNode(text: "MERLIN_NET: \(label.text)", index: metadataTextIndex))
                metadataTextIndex += 1
                continue
            }
            let head: String
            switch label.kind {
            case .local:
                head = "label"
            case .global:
                head = "global_label"
            case .hierarchical:
                head = "hierarchical_label"
            }
            guard let at = label.at else {
                nodes.append(.list([.atom(head), .string(label.text)]))
                continue
            }
            nodes.append(.list([
                .atom(head),
                .string(label.text),
                .list([.atom("at"), .atom(numberString(at.x)), .atom(numberString(at.y)), .atom("0")]),
                .list([
                    .atom("effects"),
                    .list([
                        .atom("font"),
                        .list([.atom("size"), .atom("1.27"), .atom("1.27")]),
                    ]),
                ]),
                .list([.atom("uuid"), .string(stableTextUUID("label", label.text, numberString(at.x), numberString(at.y)))]),
            ]))
        }

        for sheet in document.sheets {
            var sheetNodes: [KiCadSExpression] = [.atom("sheet")]
            if let uuid = sheet.uuid {
                sheetNodes.append(.list([.atom("uuid"), .string(uuid)]))
            }
            sheetNodes.append(.list([.atom("name"), .string(sheet.name)]))
            sheetNodes.append(.list([.atom("file"), .string(sheet.file)]))
            for pin in sheet.pins {
                sheetNodes.append(.list([.atom("pin"), .string(pin.name), .atom(pin.kind)]))
            }
            nodes.append(.list(sheetNodes))
        }

        nodes.append(contentsOf: trailingOpaqueNodes)
        return render(.list(nodes))
    }

    private func merlinComponentMetadata(for symbol: KiCadSchematicDocument.Symbol) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: symbol.properties,
            options: [.sortedKeys]
        )) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "MERLIN_COMPONENT: \(json)"
    }

    private var hiddenPropertyNames: Set<String> {
        ["Symbol", "Source", "SourceEvidence", "Pins", "Role"]
    }

    private func propertyNode(
        key: String,
        value: String,
        at: KiCadSchematicDocument.Point,
        hidden: Bool
    ) -> KiCadSExpression {
        var effects: [KiCadSExpression] = [
            .atom("effects"),
            .list([
                .atom("font"),
                .list([.atom("size"), .atom("1.27"), .atom("1.27")]),
            ]),
        ]
        if hidden {
            effects.append(.atom("hide"))
        }
        return .list([
            .atom("property"),
            .string(key),
            .string(value),
            .list([.atom("at"), .atom(numberString(at.x)), .atom(numberString(at.y)), .atom("0")]),
            .list(effects),
        ])
    }

    private func symbolPlacement(index: Int) -> KiCadSchematicDocument.Point {
        let column = index % 4
        let row = index / 4
        return KiCadSchematicDocument.Point(
            x: 25.4 + Double(column) * 50.8,
            y: 25.4 + Double(row) * 38.1
        )
    }

    private func pinNumbers(for symbol: KiCadSchematicDocument.Symbol) -> [String] {
        guard let pins = symbol.properties["Pins"] else { return [] }
        return pins
            .split(separator: ",")
            .compactMap { entry in
                entry.split(separator: ":").first.map(String.init)
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func metadataTextNode(text: String, index: Int) -> KiCadSExpression {
        let y = 250.0 + (Double(index) * 2.54)
        let yText = numberString(y)
        let uuid = stableTextUUID(text, String(index))
        return .list([
            .atom("text"),
            .string(text),
            .list([.atom("exclude_from_sim"), .atom("no")]),
            .list([.atom("at"), .atom("320"), .atom(yText), .atom("0")]),
            .list([
                .atom("effects"),
                .list([
                    .atom("font"),
                    .list([.atom("size"), .atom("1.27"), .atom("1.27")]),
                ]),
                .list([.atom("justify"), .atom("left"), .atom("bottom")]),
            ]),
            .list([.atom("uuid"), .string(uuid)]),
        ])
    }

    private func stableTextUUID(_ parts: String...) -> String {
        let input = parts.joined(separator: "|")
        let hash = input.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func numberString(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(value)
    }

    private func render(_ expression: KiCadSExpression) -> String {
        switch expression {
        case .atom(let value):
            return value
        case .string(let value):
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case .list(let nodes):
            let rendered = nodes.map(render).joined(separator: " ")
            return "(\(rendered))"
        }
    }
}

struct KiCadLibraryIDCanonicalizer {
    static func canonical(_ symbol: String) -> String {
        switch symbol {
        case "Device:Q_NPN_BCE":
            return "Transistor_BJT:Q_NPN_BCE"
        case "Device:Bridge_Rectifier":
            return "Device:D_Bridge_+-AA"
        case "Device:CP":
            return "Device:C_Polarized"
        case "Device:R_POT":
            return "Device:R_Potentiometer"
        case "Connector:AudioJack2":
            return "Connector_Audio:AudioJack2"
        case "Connector:Conn_01x02_Pin":
            return "Connector:Conn_01x02_Pin"
        default:
            return symbol
        }
    }
}

struct KiCadEmbeddedSymbolLibraryBuilder: Sendable {
    func libSymbolsNode(for requestedSymbols: [String]) -> KiCadSExpression {
        let canonicalIDs = stableUnique(requestedSymbols.map(KiCadLibraryIDCanonicalizer.canonical))
        let symbols = canonicalIDs.compactMap { id -> KiCadSExpression? in
            guard let block = symbolBlock(for: id),
                  let expression = try? KiCadSchematicParser().parseFragment(block) else {
                return nil
            }
            return expression
        }
        return .list([.atom("lib_symbols")] + symbols)
    }

    private func symbolBlock(for libID: String) -> String? {
        let parts = libID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let libraryName = parts[0]
        let symbolName = parts[1]
        guard let roots = KiCadLibraryRootDiscovery().discover() else { return nil }
        let file = roots.symbolRoot.appendingPathComponent("\(libraryName).kicad_sym")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              var block = block(named: "symbol", quotedName: symbolName, in: text) else {
            return nil
        }
        block = block.replacingOccurrences(
            of: "(symbol \"\(symbolName)\"",
            with: "(symbol \"\(libID)\"",
            options: [],
            range: block.startIndex..<block.endIndex
        )
        return block
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func block(named name: String, quotedName: String, in text: String) -> String? {
        let marker = "(\(name) \"\(quotedName)\""
        var searchStart = text.startIndex
        while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            guard isTopLevelLibrarySymbol(at: range.lowerBound, in: text),
                  let end = balancedBlockEnd(startingAt: range.lowerBound, in: text) else {
                searchStart = range.upperBound
                continue
            }
            return String(text[range.lowerBound..<end])
        }
        return nil
    }

    private func isTopLevelLibrarySymbol(at start: String.Index, in text: String) -> Bool {
        guard start > text.startIndex else { return true }
        var index = text.index(before: start)
        while index > text.startIndex {
            let character = text[index]
            if character == "\n" {
                let line = text[text.index(after: index)..<start]
                return line.allSatisfy { $0 == "\t" || $0 == " " }
            }
            index = text.index(before: index)
        }
        return true
    }

    private func balancedBlockEnd(startingAt start: String.Index, in text: String) -> String.Index? {
        var index = start
        var depth = 0
        var inString = false
        var escaped = false
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
                    return text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

struct KiCadSymbolPinGeometry: Sendable, Equatable {
    var number: String
    var name: String
    var electricalType: String
    var at: KiCadSchematicDocument.Point
}

struct KiCadSymbolGeometry: Sendable, Equatable {
    var libraryID: String
    var pins: [KiCadSymbolPinGeometry]

    func pin(number: String, name: String) -> KiCadSymbolPinGeometry? {
        pins.first { pin in
            let numberMatches = pin.number == number || pin.name == number
            let nameMatches = name.isEmpty || pin.number == name || pin.name == name
            return numberMatches && nameMatches
        }
    }
}

struct KiCadSymbolGeometryResolver: Sendable {
    private let roots: KiCadLibraryRoots?
    private let cache: KiCadSymbolGeometryCache

    init(
        roots: KiCadLibraryRoots? = KiCadLibraryRootDiscovery().discover(),
        cache: KiCadSymbolGeometryCache = KiCadSymbolGeometryCache()
    ) {
        self.roots = roots
        self.cache = cache
    }

    func resolve(libraryID: String) -> KiCadSymbolGeometry? {
        let canonicalID = KiCadLibraryIDCanonicalizer.canonical(libraryID)
        if let cached = cache.geometry(for: canonicalID) {
            return cached
        }
        let parts = canonicalID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let roots else { return nil }
        let file = roots.symbolRoot.appendingPathComponent("\(parts[0]).kicad_sym")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let block = block(named: "symbol", quotedName: parts[1], in: text),
              let expression = try? KiCadSchematicParser().parseFragment(block) else {
            return nil
        }
        let pins = pinNodes(in: expression).compactMap(parsePinGeometry)
        guard !pins.isEmpty else { return nil }
        let geometry = KiCadSymbolGeometry(libraryID: canonicalID, pins: pins)
        cache.set(geometry, for: canonicalID)
        return geometry
    }

    private func parsePinGeometry(_ expression: KiCadSExpression) -> KiCadSymbolPinGeometry? {
        guard case .list(let nodes) = expression,
              nodes.count >= 3,
              case .atom(let electricalType) = nodes[1] else {
            return nil
        }
        var at: KiCadSchematicDocument.Point?
        var name: String?
        var number: String?

        for node in nodes.dropFirst(3) {
            guard case .list(let child) = node,
                  let head = child.first?.atomValue else {
                continue
            }
            switch head {
            case "at":
                if child.count >= 3,
                   let x = child[1].doubleValue,
                   let y = child[2].doubleValue {
                    at = KiCadSchematicDocument.Point(x: x, y: y)
                }
            case "name":
                name = child.dropFirst().first?.stringOrAtomValue
            case "number":
                number = child.dropFirst().first?.stringOrAtomValue
            default:
                break
            }
        }

        guard let at,
              let number,
              let name else { return nil }
        return KiCadSymbolPinGeometry(
            number: number,
            name: name,
            electricalType: electricalType,
            at: at
        )
    }

    private func pinNodes(in expression: KiCadSExpression) -> [KiCadSExpression] {
        guard case .list(let nodes) = expression else { return [] }
        return nodes.flatMap { node -> [KiCadSExpression] in
            if node.listHead == "pin" {
                return [node]
            }
            return pinNodes(in: node)
        }
    }

    private func block(named name: String, quotedName: String, in text: String) -> String? {
        let marker = "(\(name) \"\(quotedName)\""
        var searchStart = text.startIndex
        while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            guard isTopLevelLibrarySymbol(at: range.lowerBound, in: text),
                  let end = balancedBlockEnd(startingAt: range.lowerBound, in: text) else {
                searchStart = range.upperBound
                continue
            }
            return String(text[range.lowerBound..<end])
        }
        return nil
    }

    private func isTopLevelLibrarySymbol(at start: String.Index, in text: String) -> Bool {
        guard start > text.startIndex else { return true }
        var index = text.index(before: start)
        while index > text.startIndex {
            let character = text[index]
            if character == "\n" {
                let line = text[text.index(after: index)..<start]
                return line.allSatisfy { $0 == "\t" || $0 == " " }
            }
            index = text.index(before: index)
        }
        return true
    }

    private func balancedBlockEnd(startingAt start: String.Index, in text: String) -> String.Index? {
        var index = start
        var depth = 0
        var inString = false
        var escaped = false
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
                    return text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

final class KiCadSymbolGeometryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var geometries: [String: KiCadSymbolGeometry] = [:]

    func geometry(for libraryID: String) -> KiCadSymbolGeometry? {
        lock.lock()
        defer { lock.unlock() }
        return geometries[libraryID]
    }

    func set(_ geometry: KiCadSymbolGeometry, for libraryID: String) {
        lock.lock()
        defer { lock.unlock() }
        geometries[libraryID] = geometry
    }
}

private extension KiCadSExpression {
    var listHead: String? {
        guard case .list(let nodes) = self else { return nil }
        return nodes.first?.atomValue
    }

    var atomValue: String? {
        if case .atom(let value) = self { return value }
        return nil
    }

    var stringOrAtomValue: String? {
        switch self {
        case .atom(let value), .string(let value):
            return value
        case .list:
            return nil
        }
    }

    var doubleValue: Double? {
        guard let value = stringOrAtomValue else { return nil }
        return Double(value)
    }
}
