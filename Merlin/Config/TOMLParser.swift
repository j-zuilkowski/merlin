import Foundation

struct TOMLParser {
    private struct PathKey: Hashable, Sendable {
        var segments: [String]
    }

    private enum ScopeSegment: Sendable {
        case table(String)
        case arrayItem(String, Int)
    }

    private enum ValueKind {
        case string
        case integer
        case float
        case bool
        case datetime
        case array
        case table
    }

    private var source: String
    private var index: String.Index
    private var root: [String: TOMLValue] = [:]
    private var currentScope: [ScopeSegment] = []
    private var definedTables: Set<PathKey> = []
    private var definedArrayTables: Set<PathKey> = []

    static func parse(_ source: String) throws -> [String: TOMLValue] {
        var parser = TOMLParser(source: source)
        return try parser.parseDocument()
    }

    private init(source: String) {
        self.source = source
        self.index = source.startIndex
    }

    private mutating func parseDocument() throws -> [String: TOMLValue] {
        while !atEnd {
            skipWhitespaceAndNewlines()
            guard !atEnd else { break }
            if current == "#" {
                skipComment()
                continue
            }
            if current == "[" {
                try parseTableHeader()
                continue
            }
            try parseKeyValue()
        }
        return root
    }

    private mutating func parseTableHeader() throws {
        advance()
        let isArray = match("[")
        skipInlineWhitespace()
        let path = try parseKeyPath()
        skipInlineWhitespace()
        try expect("]")
        if isArray {
            try expect("]")
        }
        skipInlineWhitespace()
        if !atEnd, current == "#" {
            skipComment()
        }
        skipWhitespaceAndNewlines()

        var root = root
        var definedTables = definedTables
        var definedArrayTables = definedArrayTables
        currentScope = try Self.insertHeader(
            into: &root,
            path: path,
            index: 0,
            prefix: [],
            scopePrefix: [],
            isArray: isArray,
            definedTables: &definedTables,
            definedArrayTables: &definedArrayTables
        )
        self.root = root
        self.definedTables = definedTables
        self.definedArrayTables = definedArrayTables
    }

    private static func insertHeader(
        into table: inout [String: TOMLValue],
        path: [String],
        index: Int,
        prefix: [String],
        scopePrefix: [ScopeSegment],
        isArray: Bool,
        definedTables: inout Set<PathKey>,
        definedArrayTables: inout Set<PathKey>
    ) throws -> [ScopeSegment] {
        let key = path[index]
        let currentPrefix = prefix + [key]
        let pathKey = PathKey(segments: currentPrefix)
        let isLast = index == path.count - 1

        if isLast {
            if isArray {
                if definedTables.contains(pathKey) {
                    throw TOMLError.keyRedefinition(currentPrefix.joined(separator: "."))
                }
                switch table[key] {
                case .array(var values):
                    values.append(.table([:]))
                    table[key] = .array(values)
                    definedArrayTables.insert(pathKey)
                    return scopePrefix + [.arrayItem(key, values.count - 1)]
                case .none:
                    table[key] = .array([.table([:])])
                    definedArrayTables.insert(pathKey)
                    return scopePrefix + [.arrayItem(key, 0)]
                default:
                    throw TOMLError.keyRedefinition(currentPrefix.joined(separator: "."))
                }
            } else {
                if definedArrayTables.contains(pathKey) {
                    throw TOMLError.keyRedefinition(currentPrefix.joined(separator: "."))
                }
                if definedTables.contains(pathKey) {
                    throw TOMLError.duplicateKey(currentPrefix.joined(separator: "."))
                }
                switch table[key] {
                case .none:
                    table[key] = .table([:])
                    definedTables.insert(pathKey)
                    return scopePrefix + [.table(key)]
                case .table:
                    definedTables.insert(pathKey)
                    return scopePrefix + [.table(key)]
                default:
                    throw TOMLError.keyRedefinition(currentPrefix.joined(separator: "."))
                }
            }
        }

        switch table[key] {
        case .none:
            table[key] = .table([:])
            definedTables.insert(pathKey)
            guard case .table(var child) = table[key] else {
                throw TOMLError.keyRedefinition(currentPrefix.joined(separator: "."))
            }
            let scope = try Self.insertHeader(
                into: &child,
                path: path,
                index: index + 1,
                prefix: currentPrefix,
                scopePrefix: scopePrefix + [.table(key)],
                isArray: isArray,
                definedTables: &definedTables,
                definedArrayTables: &definedArrayTables
            )
            table[key] = .table(child)
            return scope

        case .table(var child):
            let scope = try Self.insertHeader(
                into: &child,
                path: path,
                index: index + 1,
                prefix: currentPrefix,
                scopePrefix: scopePrefix + [.table(key)],
                isArray: isArray,
                definedTables: &definedTables,
                definedArrayTables: &definedArrayTables
            )
            table[key] = .table(child)
            return scope

        case .array(var values):
            guard values.isEmpty == false else {
                values.append(.table([:]))
                table[key] = .array(values)
                guard case .table(var child) = values[0] else {
                    throw TOMLError.keyRedefinition(currentPrefix.joined(separator: "."))
                }
                let scope = try Self.insertHeader(
                    into: &child,
                    path: path,
                    index: index + 1,
                    prefix: currentPrefix,
                    scopePrefix: scopePrefix + [.arrayItem(key, 0)],
                    isArray: isArray,
                    definedTables: &definedTables,
                    definedArrayTables: &definedArrayTables
                )
                values[0] = .table(child)
                table[key] = .array(values)
                return scope
            }
            let lastIndex = values.count - 1
            guard case .table(var child) = values[lastIndex] else {
                throw TOMLError.keyRedefinition(currentPrefix.joined(separator: "."))
            }
            let scope = try Self.insertHeader(
                into: &child,
                path: path,
                index: index + 1,
                prefix: currentPrefix,
                scopePrefix: scopePrefix + [.arrayItem(key, lastIndex)],
                isArray: isArray,
                definedTables: &definedTables,
                definedArrayTables: &definedArrayTables
            )
            values[lastIndex] = .table(child)
            table[key] = .array(values)
            return scope

        default:
            throw TOMLError.keyRedefinition(currentPrefix.joined(separator: "."))
        }
    }

    private mutating func parseKeyValue() throws {
        let keys = try parseKeyPath()
        skipInlineWhitespace()
        try expect("=")
        skipInlineWhitespace()
        let value = try parseValue()
        skipInlineWhitespace()
        if !atEnd, current == "#" {
            skipComment()
        }
        skipWhitespaceAndNewlines()

        var root = root
        var definedTables = definedTables
        let scope = currentScope
        let scopePath = Self.logicalPath(for: scope)
        try Self.modifyTable(in: &root, scope: scope) { table in
            try Self.setValue(
                value,
                in: &table,
                keys: keys,
                prefix: scopePath,
                definedTables: &definedTables
            )
        }
        self.root = root
        self.definedTables = definedTables
    }

    private static func setValue(
        _ value: TOMLValue,
        in table: inout [String: TOMLValue],
        keys: [String],
        prefix: [String],
        definedTables: inout Set<PathKey>
    ) throws {
        try setValue(value, in: &table, keys: keys, prefix: prefix, index: 0, definedTables: &definedTables)
    }

    private static func setValue(
        _ value: TOMLValue,
        in table: inout [String: TOMLValue],
        keys: [String],
        prefix: [String],
        index: Int,
        definedTables: inout Set<PathKey>
    ) throws {
        let key = keys[index]
        let path = PathKey(segments: prefix + Array(keys.prefix(index + 1)))
        if index == keys.count - 1 {
            guard table[key] == nil else {
                throw TOMLError.duplicateKey(path.segments.joined(separator: "."))
            }
            table[key] = value
            return
        }

        if table[key] == nil {
            table[key] = .table([:])
            definedTables.insert(path)
        }

        guard case .table(var child) = table[key] else {
            throw TOMLError.keyRedefinition(path.segments.joined(separator: "."))
        }
        try setValue(
            value,
            in: &child,
            keys: keys,
            prefix: prefix + [key],
            index: index + 1,
            definedTables: &definedTables
        )
        table[key] = .table(child)
    }

    private static func modifyTable<R>(
        in table: inout [String: TOMLValue],
        scope: [ScopeSegment],
        body: (inout [String: TOMLValue]) throws -> R
    ) throws -> R {
        guard let head = scope.first else {
            return try body(&table)
        }

        switch head {
        case .table(let key):
            guard case .table(var child) = table[key] else {
                throw TOMLError.keyRedefinition(key)
            }
            let result = try modifyTable(in: &child, scope: Array(scope.dropFirst()), body: body)
            table[key] = .table(child)
            return result

        case .arrayItem(let key, let index):
            guard case .array(var values) = table[key], values.indices.contains(index) else {
                throw TOMLError.unexpectedToken("array-of-tables navigation failed for \(key)")
            }
            guard case .table(var child) = values[index] else {
                throw TOMLError.unexpectedToken("expected table in array at \(key)[\(index)]")
            }
            let result = try modifyTable(in: &child, scope: Array(scope.dropFirst()), body: body)
            values[index] = .table(child)
            table[key] = .array(values)
            return result
        }
    }

    private static func logicalPath(for scope: [ScopeSegment]) -> [String] {
        scope.map { segment in
            switch segment {
            case .table(let key):
                return key
            case .arrayItem(let key, _):
                return key
            }
        }
    }

    private mutating func parseValue() throws -> TOMLValue {
        guard !atEnd else {
            throw TOMLError.unexpectedToken("EOF")
        }

        switch current {
        case "\"":
            if peek(offset: 1) == "\"" && peek(offset: 2) == "\"" {
                return .string(try parseBasicString(multiline: true))
            }
            return .string(try parseBasicString(multiline: false))
        case "'":
            if peek(offset: 1) == "'" && peek(offset: 2) == "'" {
                return .string(try parseLiteralString(multiline: true))
            }
            return .string(try parseLiteralString(multiline: false))
        case "[":
            return try parseArray()
        case "{":
            return try parseInlineTable()
        case "t":
            guard consumeLiteral("true") else {
                throw TOMLError.invalidValue("t")
            }
            return .bool(true)
        case "f":
            guard consumeLiteral("false") else {
                throw TOMLError.invalidValue("f")
            }
            return .bool(false)
        default:
            return try parseNumberOrDatetime()
        }
    }

    private mutating func parseArray() throws -> TOMLValue {
        try expect("[")
        skipWhitespaceAndNewlines()
        if !atEnd, current == "]" {
            advance()
            return .array([])
        }

        var values: [TOMLValue] = []
        var firstKind: ValueKind?

        while true {
            skipWhitespaceAndNewlines()
            if !atEnd, current == "#" {
                skipComment()
                continue
            }
            if !atEnd, current == "]" {
                advance()
                break
            }

            let value = try parseValue()
            let kind = valueKind(of: value)
            if let firstKind, firstKind != kind {
                throw TOMLError.arrayTypeMismatch
            }
            firstKind = firstKind ?? kind
            values.append(value)

            skipWhitespaceAndNewlines()
            if !atEnd, current == "#" {
                skipComment()
                continue
            }
            if !atEnd, current == "," {
                advance()
                continue
            }
            if !atEnd, current == "]" {
                advance()
                break
            }
        }

        return .array(values)
    }

    private mutating func parseInlineTable() throws -> TOMLValue {
        try expect("{")
        skipWhitespaceAndNewlines()
        if !atEnd, current == "}" {
            advance()
            return .table([:])
        }

        var values: [String: TOMLValue] = [:]
        while true {
            skipWhitespaceAndNewlines()
            if !atEnd, current == "#" {
                skipComment()
                continue
            }
            if !atEnd, current == "}" {
                advance()
                break
            }

            let keys = try parseKeyPath(terminators: [":", "=", ",", "}"])
            skipInlineWhitespace()
            try expect("=")
            skipInlineWhitespace()
            let value = try parseValue()
            var definedTables = self.definedTables
            try Self.setValue(
                value,
                in: &values,
                keys: keys,
                prefix: [],
                definedTables: &definedTables
            )
            self.definedTables = definedTables

            skipWhitespaceAndNewlines()
            if !atEnd, current == "#" {
                skipComment()
                continue
            }
            if !atEnd, current == "," {
                advance()
                continue
            }
            if !atEnd, current == "}" {
                advance()
                break
            }
        }
        return .table(values)
    }

    private mutating func parseNumberOrDatetime() throws -> TOMLValue {
        let token = readToken()
        let cleaned = token.replacingOccurrences(of: "_", with: "")

        if let date = parseDatetime(cleaned) {
            return .datetime(date)
        }

        if cleaned.hasPrefix("0x") || cleaned.hasPrefix("+0x") || cleaned.hasPrefix("-0x") {
            let sign: Int
            let digits: Substring
            if cleaned.hasPrefix("-0x") {
                sign = -1
                digits = cleaned.dropFirst(3)
            } else if cleaned.hasPrefix("+0x") {
                sign = 1
                digits = cleaned.dropFirst(3)
            } else {
                sign = 1
                digits = cleaned.dropFirst(2)
            }
            guard let value = Int(digits, radix: 16) else {
                throw TOMLError.invalidValue(token)
            }
            return .integer(sign * value)
        }

        if cleaned.contains(".") || cleaned.contains("e") || cleaned.contains("E") {
            guard let value = Double(cleaned) else {
                throw TOMLError.invalidValue(token)
            }
            return .float(value)
        }

        if let value = Int(cleaned) {
            return .integer(value)
        }

        if let value = Double(cleaned) {
            return .float(value)
        }

        throw TOMLError.invalidValue(token)
    }

    private func parseDatetime(_ token: String) -> Date? {
        guard token.contains("T") || token.contains(":") else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: token) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: token)
    }

    private mutating func parseBasicString(multiline: Bool) throws -> String {
        if multiline {
            try expect("\"")
            try expect("\"")
            try expect("\"")
            if !atEnd, current == "\n" {
                advance()
            } else if !atEnd, current == "\r" {
                advance()
                if !atEnd, current == "\n" {
                    advance()
                }
            }
        } else {
            try expect("\"")
        }

        var result = ""
        while !atEnd {
            if multiline, current == "\"" && peek(offset: 1) == "\"" && peek(offset: 2) == "\"" {
                advance()
                advance()
                advance()
                return result
            }
            if !multiline, current == "\"" {
                advance()
                return result
            }
            if !multiline, current == "\n" {
                throw TOMLError.unterminatedString
            }
            if current == "\\" {
                advance()
                result.append(try parseEscape())
            } else {
                result.append(current)
                advance()
            }
        }

        throw TOMLError.unterminatedString
    }

    private mutating func parseLiteralString(multiline: Bool) throws -> String {
        if multiline {
            try expect("'")
            try expect("'")
            try expect("'")
            if !atEnd, current == "\n" {
                advance()
            } else if !atEnd, current == "\r" {
                advance()
                if !atEnd, current == "\n" {
                    advance()
                }
            }
        } else {
            try expect("'")
        }

        var result = ""
        while !atEnd {
            if multiline, current == "'" && peek(offset: 1) == "'" && peek(offset: 2) == "'" {
                advance()
                advance()
                advance()
                return result
            }
            if !multiline, current == "'" {
                advance()
                return result
            }
            if !multiline, current == "\n" {
                throw TOMLError.unterminatedString
            }
            result.append(current)
            advance()
        }

        throw TOMLError.unterminatedString
    }

    private mutating func parseEscape() throws -> Character {
        guard !atEnd else {
            throw TOMLError.unterminatedString
        }

        let escaped = current
        advance()
        switch escaped {
        case "b": return "\u{0008}"
        case "t": return "\t"
        case "n": return "\n"
        case "f": return "\u{000C}"
        case "r": return "\r"
        case "\"": return "\""
        case "\\": return "\\"
        case "u":
            return try parseUnicodeEscape(length: 4)
        case "U":
            return try parseUnicodeEscape(length: 8)
        default:
            throw TOMLError.invalidEscape(escaped)
        }
    }

    private mutating func parseUnicodeEscape(length: Int) throws -> Character {
        var digits = ""
        for _ in 0..<length {
            guard !atEnd, current.isHexDigit else {
                throw TOMLError.invalidUnicodeScalar(digits)
            }
            digits.append(current)
            advance()
        }
        guard let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) else {
            throw TOMLError.invalidUnicodeScalar(digits)
        }
        return Character(scalar)
    }

    private mutating func parseKeyPath(terminators: Set<Character> = ["=", "]"]) throws -> [String] {
        var keys: [String] = []
        while true {
            let key = try parseKeySegment(terminators: terminators)
            keys.append(key)
            skipInlineWhitespace()
            if !atEnd, current == "." {
                advance()
                skipInlineWhitespace()
                continue
            }
            break
        }
        return keys
    }

    private mutating func parseKeySegment(terminators: Set<Character>) throws -> String {
        skipInlineWhitespace()
        guard !atEnd else {
            throw TOMLError.unexpectedToken("EOF in key")
        }

        if current == "\"" {
            return try parseBasicKey()
        }
        if current == "'" {
            return try parseLiteralKey()
        }

        var result = ""
        while !atEnd {
            let character = current
            if character.isWhitespace || character == "." || character == "#" || character == "," || character == "{" || character == "}" || terminators.contains(character) {
                break
            }
            result.append(character)
            advance()
        }

        guard result.isEmpty == false else {
            throw TOMLError.unexpectedToken("empty key")
        }
        return result
    }

    private mutating func parseBasicKey() throws -> String {
        try parseBasicString(multiline: false)
    }

    private mutating func parseLiteralKey() throws -> String {
        try parseLiteralString(multiline: false)
    }

    private mutating func readToken() -> String {
        var result = ""
        while !atEnd {
            let character = current
            if character.isWhitespace || character == "," || character == "]" || character == "}" || character == "#" {
                break
            }
            result.append(character)
            advance()
        }
        return result
    }

    private func valueKind(of value: TOMLValue) -> ValueKind {
        switch value {
        case .string:
            return .string
        case .integer:
            return .integer
        case .float:
            return .float
        case .bool:
            return .bool
        case .datetime:
            return .datetime
        case .array:
            return .array
        case .table:
            return .table
        }
    }

    private mutating func consumeLiteral(_ literal: String) -> Bool {
        var cursor = index
        for character in literal {
            guard cursor < source.endIndex, source[cursor] == character else {
                return false
            }
            cursor = source.index(after: cursor)
        }
        index = cursor
        return true
    }

    private mutating func skipWhitespaceAndNewlines() {
        while !atEnd {
            let character = current
            if character == " " || character == "\t" || character == "\n" || character == "\r" {
                advance()
            } else {
                break
            }
        }
    }

    private mutating func skipInlineWhitespace() {
        while !atEnd {
            let character = current
            if character == " " || character == "\t" {
                advance()
            } else {
                break
            }
        }
    }

    private mutating func skipComment() {
        while !atEnd, current != "\n", current != "\r" {
            advance()
        }
    }

    private mutating func expect(_ character: Character) throws {
        guard !atEnd, current == character else {
            throw TOMLError.unexpectedToken(atEnd ? "EOF" : String(current))
        }
        advance()
    }

    private mutating func match(_ character: Character) -> Bool {
        guard !atEnd, current == character else {
            return false
        }
        advance()
        return true
    }

    private mutating func advance() {
        index = source.index(after: index)
    }

    private var atEnd: Bool {
        index >= source.endIndex
    }

    private var current: Character {
        source[index]
    }

    private func peek(offset: Int) -> Character? {
        var cursor = index
        for _ in 0..<offset {
            guard cursor < source.endIndex else {
                return nil
            }
            cursor = source.index(after: cursor)
        }
        guard cursor < source.endIndex else {
            return nil
        }
        return source[cursor]
    }
}
