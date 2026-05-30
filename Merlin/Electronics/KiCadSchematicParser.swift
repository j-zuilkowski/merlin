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

    private func parseSymbol(_ expression: KiCadSExpression) throws -> KiCadSchematicDocument.Symbol {
        guard case .list(let list) = expression else {
            throw KiCadSchematicParserError.malformed("symbol must be a list")
        }

        var uuid: String?
        var properties: [String: String] = [:]

        for item in list.dropFirst() {
            guard case .list(let child) = item,
                  let head = child.first?.atomValue else {
                continue
            }

            if head == "uuid", let value = child.dropFirst().first?.stringOrAtomValue {
                uuid = value
            }

            if head == "property",
               child.count >= 3,
               let key = child[1].stringOrAtomValue,
               let value = child[2].stringOrAtomValue {
                properties[key] = value
            }
        }

        return KiCadSchematicDocument.Symbol(uuid: uuid, properties: properties, emitsKiCadSymbol: true)
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

        return KiCadSchematicDocument.Label(kind: kind, text: text, emitsKiCadConnectivity: true)
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
            return .net(KiCadSchematicDocument.Label(kind: .local, text: name, emitsKiCadConnectivity: false))
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

        for symbol in document.symbols {
            if !symbol.emitsKiCadSymbol {
                nodes.append(metadataTextNode(text: merlinComponentMetadata(for: symbol), index: metadataTextIndex))
                metadataTextIndex += 1
                continue
            }
            var symbolNodes: [KiCadSExpression] = [.atom("symbol")]
            if let uuid = symbol.uuid {
                symbolNodes.append(.list([.atom("uuid"), .string(uuid)]))
            }
            for key in symbol.properties.keys.sorted() {
                if let value = symbol.properties[key] {
                    symbolNodes.append(.list([.atom("property"), .string(key), .string(value)]))
                }
            }
            nodes.append(.list(symbolNodes))
        }

        for wire in document.wires {
            nodes.append(.list([
                .atom("wire"),
                .list([
                    .atom("pts"),
                    .list([.atom("xy"), .atom(numberString(wire.start.x)), .atom(numberString(wire.start.y))]),
                    .list([.atom("xy"), .atom(numberString(wire.end.x)), .atom(numberString(wire.end.y))]),
                ]),
            ]))
        }

        for junction in document.junctions {
            nodes.append(.list([
                .atom("junction"),
                .list([.atom("at"), .atom(numberString(junction.at.x)), .atom(numberString(junction.at.y))]),
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
            nodes.append(.list([.atom(head), .string(label.text)]))
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

        nodes.append(contentsOf: document.opaqueNodes)
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

private extension KiCadSExpression {
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
