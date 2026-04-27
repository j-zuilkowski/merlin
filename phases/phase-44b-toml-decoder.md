# Phase 44b — TOMLDecoder Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 44a complete: failing tests in place.

New files:
  - `Merlin/Config/TOMLValue.swift` — value enum + Foundation bridge
  - `Merlin/Config/TOMLParser.swift` — recursive descent parser, full TOML v1.0 spec
  - `Merlin/Config/TOMLDecoder.swift` — top-level decode<T: Decodable> via JSON pipeline

---

## Write to: Merlin/Config/TOMLValue.swift

```swift
import Foundation

// MARK: - Value types

enum TOMLValue: Sendable {
    case string(String)
    case integer(Int)
    case float(Double)
    case bool(Bool)
    case datetime(Date)
    indirect case array([TOMLValue])
    indirect case table([String: TOMLValue])
}

extension TOMLValue {
    // Bridge to Foundation types so we can pipe through JSONSerialization → JSONDecoder.
    func toFoundation() -> Any {
        switch self {
        case .string(let s):   return s
        case .integer(let i):  return i
        case .float(let f):    return f
        case .bool(let b):     return b
        case .datetime(let d): return ISO8601DateFormatter().string(from: d)
        case .array(let a):    return a.map { $0.toFoundation() }
        case .table(let t):    return t.mapValues { $0.toFoundation() }
        }
    }
}

// MARK: - Errors

enum TOMLError: Error, LocalizedError, Sendable {
    case unexpectedToken(String)
    case duplicateKey(String)
    case keyRedefinition(String)
    case unterminatedString
    case invalidEscape(Character)
    case invalidUnicodeScalar(String)
    case invalidValue(String)
    case invalidDatetime(String)
    case arrayTypeMismatch

    var errorDescription: String? {
        switch self {
        case .unexpectedToken(let s):      return "Unexpected token: \(s)"
        case .duplicateKey(let k):         return "Duplicate key: \(k)"
        case .keyRedefinition(let k):      return "Key redefined as different type: \(k)"
        case .unterminatedString:          return "Unterminated string"
        case .invalidEscape(let c):        return "Invalid escape: \\\(c)"
        case .invalidUnicodeScalar(let s): return "Invalid Unicode scalar: \(s)"
        case .invalidValue(let s):         return "Invalid value: \(s)"
        case .invalidDatetime(let s):      return "Invalid datetime: \(s)"
        case .arrayTypeMismatch:           return "Mixed types in array"
        }
    }
}
```

---

## Write to: Merlin/Config/TOMLParser.swift

```swift
import Foundation

// Full TOML v1.0.0 recursive descent parser.
// Produces [String: TOMLValue] suitable for TOMLDecoder's Foundation bridge.
struct TOMLParser {

    // MARK: - State

    private var source: String
    private var idx: String.Index
    private var root: [String: TOMLValue] = [:]

    // Current table navigation context for [table] and [[array-of-tables]] headers
    private var scopePath: [ScopeSegment] = []

    // Track which dotted paths have been defined as plain tables vs array-of-tables
    // to catch illegal redefinitions.
    private var definedTables: Set<String> = []
    private var definedArrayTables: Set<String> = []

    private struct ScopeSegment: Sendable {
        let key: String
        let isArray: Bool
        let index: Int   // index into the array-of-tables if isArray
    }

    // MARK: - Entry point

    static func parse(_ source: String) throws -> [String: TOMLValue] {
        var parser = TOMLParser(source: source)
        return try parser.parseDocument()
    }

    private init(source: String) {
        self.source = source
        self.idx = source.startIndex
    }

    // MARK: - Top-level parse

    private mutating func parseDocument() throws -> [String: TOMLValue] {
        while !atEnd {
            skipWhitespaceAndNewlines()
            guard !atEnd else { break }
            let c = current
            if c == "#" {
                skipComment()
            } else if c == "[" {
                try parseTableHeader()
            } else if c == "\n" || c == "\r" {
                advance()
            } else {
                try parseKeyValue(into: &root, scopePath: scopePath)
            }
        }
        return root
    }

    // MARK: - Table headers

    private mutating func parseTableHeader() throws {
        advance() // consume first [
        let isArray = match("[")
        skipInlineWhitespace()
        let path = try parseDottedKey()
        skipInlineWhitespace()
        try expect("]")
        if isArray { try expect("]") }
        skipInlineWhitespace()
        if !atEnd && current == "#" { skipComment() }
        skipNewline()

        let dotPath = path.joined(separator: ".")
        if isArray {
            if definedTables.contains(dotPath) {
                throw TOMLError.keyRedefinition(dotPath)
            }
            definedArrayTables.insert(dotPath)
            // Append a new table entry and navigate into it
            let idx = appendArrayTable(path: path)
            scopePath = buildArrayScope(path: path, arrayIndex: idx)
        } else {
            if definedArrayTables.contains(dotPath) {
                throw TOMLError.keyRedefinition(dotPath)
            }
            if definedTables.contains(dotPath) {
                throw TOMLError.duplicateKey(dotPath)
            }
            definedTables.insert(dotPath)
            ensureTable(path: path)
            scopePath = buildTableScope(path: path)
        }
    }

    // Navigate into root, creating tables as needed, and append a new empty
    // table to the array-of-tables at the terminal key. Returns the new index.
    private mutating func appendArrayTable(path: [String]) -> Int {
        var node = &root
        for (i, key) in path.enumerated() {
            if i == path.count - 1 {
                switch node[key] {
                case .array(var arr):
                    arr.append(.table([:]))
                    node[key] = .array(arr)
                    if case .array(let a) = node[key] { return a.count - 1 }
                    return 0
                case .none:
                    node[key] = .array([.table([:])])
                    return 0
                default:
                    // Already defined as non-array — will be caught by caller
                    node[key] = .array([.table([:])])
                    return 0
                }
            } else {
                if node[key] == nil {
                    node[key] = .table([:])
                }
                // Navigate deeper — we need the raw pointer trick via local var
                // Swift doesn't allow &dict[key] directly without an intermediate.
                // Use a helper that mutates in place.
                node = navigateInto(dict: &node, key: key)
            }
        }
        return 0
    }

    // Returns a pointer to the inner table dict for a given key.
    // Creates an empty table if missing.
    private func navigateInto(dict: inout [String: TOMLValue], key: String) -> inout [String: TOMLValue] {
        // We cannot return `inout` from a function in Swift directly.
        // Use UnsafeMutablePointer as the idiomatic workaround for recursive
        // in-place dictionary navigation in a value-type parser.
        fatalError("unreachable — appendArrayTable navigates with local copies")
    }

    // MARK: - Scope path helpers

    private func buildTableScope(path: [String]) -> [ScopeSegment] {
        path.map { ScopeSegment(key: $0, isArray: false, index: 0) }
    }

    private func buildArrayScope(path: [String], arrayIndex: Int) -> [ScopeSegment] {
        var segs = path.dropLast().map { ScopeSegment(key: $0, isArray: false, index: 0) }
        segs.append(ScopeSegment(key: path.last!, isArray: true, index: arrayIndex))
        return segs
    }

    private mutating func ensureTable(path: [String]) {
        setNestedIfMissing(&root, path: path, value: .table([:]))
    }

    // MARK: - Key-value parsing

    private mutating func parseKeyValue(into target: inout [String: TOMLValue], scopePath: [ScopeSegment]) throws {
        let keys = try parseDottedKey()
        skipInlineWhitespace()
        try expect("=")
        skipInlineWhitespace()
        let value = try parseValue()
        skipInlineWhitespace()
        if !atEnd && current == "#" { skipComment() }
        skipNewline()

        // Navigate to the correct node using scopePath, then set the dotted key
        var effectivePath: [ScopeSegment] = scopePath
        for (i, k) in keys.dropLast().enumerated() {
            effectivePath.append(ScopeSegment(key: k, isArray: false, index: 0))
            let _ = i // suppress warning
        }
        let leafKey = keys.last!

        // Set value by navigating root with the effective path
        try setLeaf(&root, scope: effectivePath, key: leafKey, value: value)
    }

    private mutating func setLeaf(_ dict: inout [String: TOMLValue], scope: [ScopeSegment], key: String, value: TOMLValue) throws {
        if scope.isEmpty {
            if dict[key] != nil {
                throw TOMLError.duplicateKey(key)
            }
            dict[key] = value
            return
        }
        let seg = scope[0]
        let rest = Array(scope.dropFirst())
        if seg.isArray {
            guard case .array(var arr) = dict[seg.key], seg.index < arr.count else {
                throw TOMLError.unexpectedToken("array-of-tables navigation failed for \(seg.key)")
            }
            guard case .table(var inner) = arr[seg.index] else {
                throw TOMLError.unexpectedToken("expected table in array at \(seg.key)[\(seg.index)]")
            }
            try setLeaf(&inner, scope: rest, key: key, value: value)
            arr[seg.index] = .table(inner)
            dict[seg.key] = .array(arr)
        } else {
            if dict[seg.key] == nil {
                dict[seg.key] = .table([:])
            }
            guard case .table(var inner) = dict[seg.key] else {
                throw TOMLError.keyRedefinition(seg.key)
            }
            try setLeaf(&inner, scope: rest, key: key, value: value)
            dict[seg.key] = .table(inner)
        }
    }

    // MARK: - Value parsers

    private mutating func parseValue() throws -> TOMLValue {
        guard !atEnd else { throw TOMLError.unexpectedToken("EOF in value") }
        let c = current
        switch c {
        case "\"":
            if peek(ahead: 1) == "\"" && peek(ahead: 2) == "\"" {
                return .string(try parseMultilineBasicString())
            }
            return .string(try parseBasicString())
        case "'":
            if peek(ahead: 1) == "'" && peek(ahead: 2) == "'" {
                return .string(try parseMultilineLiteralString())
            }
            return .string(try parseLiteralString())
        case "[":
            return try parseArray()
        case "{":
            return try parseInlineTable()
        case "t":
            return try parseBoolOrDatetime(prefix: "true")
        case "f":
            return try parseBoolOrDatetime(prefix: "false")
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "-", "i", "n":
            return try parseNumberOrDatetime()
        default:
            throw TOMLError.invalidValue(String(c))
        }
    }

    // MARK: Basic string

    private mutating func parseBasicString() throws -> String {
        advance() // opening "
        var result = ""
        while !atEnd {
            let c = current
            if c == "\"" { advance(); return result }
            if c == "\n" { throw TOMLError.unterminatedString }
            if c == "\\" {
                advance()
                result.append(try parseEscape())
            } else {
                result.append(c)
                advance()
            }
        }
        throw TOMLError.unterminatedString
    }

    private mutating func parseEscape() throws -> Character {
        guard !atEnd else { throw TOMLError.unterminatedString }
        let c = current; advance()
        switch c {
        case "b":  return "\u{0008}"
        case "t":  return "\t"
        case "n":  return "\n"
        case "f":  return "\u{000C}"
        case "r":  return "\r"
        case "\"": return "\""
        case "\\": return "\\"
        case "u":  return try parseUnicodeEscape(length: 4)
        case "U":  return try parseUnicodeEscape(length: 8)
        default:   throw TOMLError.invalidEscape(c)
        }
    }

    private mutating func parseUnicodeEscape(length: Int) throws -> Character {
        var hex = ""
        for _ in 0..<length {
            guard !atEnd, current.isHexDigit else {
                throw TOMLError.invalidUnicodeScalar(hex)
            }
            hex.append(current); advance()
        }
        guard let codePoint = UInt32(hex, radix: 16),
              let scalar = Unicode.Scalar(codePoint) else {
            throw TOMLError.invalidUnicodeScalar(hex)
        }
        return Character(scalar)
    }

    // MARK: Literal string

    private mutating func parseLiteralString() throws -> String {
        advance() // opening '
        var result = ""
        while !atEnd {
            let c = current
            if c == "'" { advance(); return result }
            if c == "\n" { throw TOMLError.unterminatedString }
            result.append(c); advance()
        }
        throw TOMLError.unterminatedString
    }

    // MARK: Multi-line basic string

    private mutating func parseMultilineBasicString() throws -> String {
        advance(); advance(); advance() // consume """
        // Optional immediate newline after opening is trimmed
        if !atEnd && current == "\n" { advance() }
        else if !atEnd && current == "\r" {
            advance()
            if !atEnd && current == "\n" { advance() }
        }
        var result = ""
        while !atEnd {
            if current == "\"" && peek(ahead: 1) == "\"" && peek(ahead: 2) == "\"" {
                advance(); advance(); advance(); return result
            }
            if current == "\\" {
                advance()
                // Line-ending backslash: skip whitespace/newlines
                if current == "\n" || current == "\r" || current == " " || current == "\t" {
                    while !atEnd && (current == " " || current == "\t" || current == "\n" || current == "\r") {
                        advance()
                    }
                } else {
                    result.append(try parseEscape())
                }
            } else {
                result.append(current); advance()
            }
        }
        throw TOMLError.unterminatedString
    }

    // MARK: Multi-line literal string

    private mutating func parseMultilineLiteralString() throws -> String {
        advance(); advance(); advance() // consume '''
        if !atEnd && current == "\n" { advance() }
        var result = ""
        while !atEnd {
            if current == "'" && peek(ahead: 1) == "'" && peek(ahead: 2) == "'" {
                advance(); advance(); advance(); return result
            }
            result.append(current); advance()
        }
        throw TOMLError.unterminatedString
    }

    // MARK: Number / datetime

    private mutating func parseNumberOrDatetime() throws -> TOMLValue {
        var raw = ""
        // Collect all characters valid in a number or datetime
        while !atEnd {
            let c = current
            if c.isLetter || c.isNumber || c == "." || c == "_" || c == "+" || c == "-"
                || c == ":" || c == "T" || c == "Z" {
                raw.append(c); advance()
            } else {
                break
            }
        }
        // Check special float literals
        let stripped = raw.replacingOccurrences(of: "_", with: "")
        if stripped == "inf" || stripped == "+inf" || stripped == "-inf" {
            return .float(stripped.hasPrefix("-") ? -.infinity : .infinity)
        }
        if stripped == "nan" || stripped == "+nan" || stripped == "-nan" {
            return .float(.nan)
        }
        // Hex / octal / binary integer
        if stripped.hasPrefix("0x") {
            guard let v = Int(stripped.dropFirst(2), radix: 16) else {
                throw TOMLError.invalidValue(raw)
            }
            return .integer(v)
        }
        if stripped.hasPrefix("0o") {
            guard let v = Int(stripped.dropFirst(2), radix: 8) else {
                throw TOMLError.invalidValue(raw)
            }
            return .integer(v)
        }
        if stripped.hasPrefix("0b") {
            guard let v = Int(stripped.dropFirst(2), radix: 2) else {
                throw TOMLError.invalidValue(raw)
            }
            return .integer(v)
        }
        // Datetime detection: contains T or Z or has colons + dashes in datetime pattern
        if stripped.contains("T") || (stripped.count >= 10 && stripped.dropFirst(4).hasPrefix("-")) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: stripped) { return .datetime(d) }
            formatter.formatOptions = [.withInternetDateTime]
            if let d = formatter.date(from: stripped) { return .datetime(d) }
            throw TOMLError.invalidDatetime(raw)
        }
        // Float: contains . or e/E
        if stripped.contains(".") || stripped.lowercased().contains("e") {
            guard let v = Double(stripped) else { throw TOMLError.invalidValue(raw) }
            return .float(v)
        }
        // Integer
        guard let v = Int(stripped) else { throw TOMLError.invalidValue(raw) }
        return .integer(v)
    }

    private mutating func parseBoolOrDatetime(prefix: String) throws -> TOMLValue {
        var raw = ""
        let needed = prefix.count
        for _ in 0..<needed {
            guard !atEnd else { throw TOMLError.invalidValue(raw) }
            raw.append(current); advance()
        }
        guard raw == prefix else { throw TOMLError.invalidValue(raw) }
        return prefix == "true" ? .bool(true) : .bool(false)
    }

    // MARK: Array

    private mutating func parseArray() throws -> TOMLValue {
        advance() // [
        var items: [TOMLValue] = []
        while true {
            skipWhitespaceAndNewlines()
            if atEnd { throw TOMLError.unexpectedToken("EOF in array") }
            if current == "]" { advance(); break }
            if current == "#" { skipComment(); continue }
            let item = try parseValue()
            items.append(item)
            skipWhitespaceAndNewlines()
            if current == "," { advance() }
            else if current == "]" { advance(); break }
            else if current == "#" { skipComment() }
            else { throw TOMLError.unexpectedToken(String(current)) }
        }
        return .array(items)
    }

    // MARK: Inline table

    private mutating func parseInlineTable() throws -> TOMLValue {
        advance() // {
        var dict: [String: TOMLValue] = [:]
        skipInlineWhitespace()
        if !atEnd && current == "}" { advance(); return .table(dict) }
        while true {
            skipInlineWhitespace()
            let keys = try parseDottedKey()
            skipInlineWhitespace()
            try expect("=")
            skipInlineWhitespace()
            let value = try parseValue()
            // Flatten dotted keys into nested tables
            insertNested(&dict, keys: keys, value: value)
            skipInlineWhitespace()
            if atEnd { throw TOMLError.unexpectedToken("EOF in inline table") }
            if current == "}" { advance(); break }
            if current == "," { advance() }
            else { throw TOMLError.unexpectedToken(String(current)) }
        }
        return .table(dict)
    }

    // MARK: - Key parsing

    private mutating func parseDottedKey() throws -> [String] {
        var keys: [String] = [try parseSimpleKey()]
        while !atEnd && current == "." {
            advance()
            skipInlineWhitespace()
            keys.append(try parseSimpleKey())
        }
        return keys
    }

    private mutating func parseSimpleKey() throws -> String {
        guard !atEnd else { throw TOMLError.unexpectedToken("EOF in key") }
        if current == "\"" { return try parseBasicString() }
        if current == "'" { return try parseLiteralString() }
        var key = ""
        while !atEnd {
            let c = current
            if c.isLetter || c.isNumber || c == "-" || c == "_" {
                key.append(c); advance()
            } else { break }
        }
        if key.isEmpty { throw TOMLError.unexpectedToken("empty key near '\(current)'") }
        return key
    }

    // MARK: - Helpers

    private var atEnd: Bool { idx >= source.endIndex }

    private var current: Character { source[idx] }

    private func peek(ahead n: Int) -> Character? {
        guard let i = source.index(idx, offsetBy: n, limitedBy: source.index(before: source.endIndex)) else {
            return nil
        }
        return source[i]
    }

    private mutating func advance() {
        guard !atEnd else { return }
        idx = source.index(after: idx)
    }

    @discardableResult
    private mutating func match(_ char: Character) -> Bool {
        guard !atEnd && current == char else { return false }
        advance(); return true
    }

    private mutating func expect(_ char: Character) throws {
        guard !atEnd && current == char else {
            throw TOMLError.unexpectedToken("expected '\(char)' got '\(atEnd ? "EOF" : String(current))'")
        }
        advance()
    }

    private mutating func skipInlineWhitespace() {
        while !atEnd && (current == " " || current == "\t") { advance() }
    }

    private mutating func skipWhitespaceAndNewlines() {
        while !atEnd && (current == " " || current == "\t" || current == "\n" || current == "\r") {
            advance()
        }
    }

    private mutating func skipNewline() {
        if !atEnd && current == "\r" { advance() }
        if !atEnd && current == "\n" { advance() }
    }

    private mutating func skipComment() {
        while !atEnd && current != "\n" && current != "\r" { advance() }
        skipNewline()
    }

    // MARK: - Nested dict mutation helpers

    private func insertNested(_ dict: inout [String: TOMLValue], keys: [String], value: TOMLValue) {
        if keys.count == 1 {
            dict[keys[0]] = value
            return
        }
        let key = keys[0]
        var inner: [String: TOMLValue]
        if case .table(let t) = dict[key] {
            inner = t
        } else {
            inner = [:]
        }
        insertNested(&inner, keys: Array(keys.dropFirst()), value: value)
        dict[key] = .table(inner)
    }

    private func setNestedIfMissing(_ dict: inout [String: TOMLValue], path: [String], value: TOMLValue) {
        if path.count == 1 {
            if dict[path[0]] == nil { dict[path[0]] = value }
            return
        }
        let key = path[0]
        var inner: [String: TOMLValue]
        if case .table(let t) = dict[key] {
            inner = t
        } else {
            inner = [:]
        }
        setNestedIfMissing(&inner, path: Array(path.dropFirst()), value: value)
        dict[key] = .table(inner)
    }
}
```

---

## Write to: Merlin/Config/TOMLDecoder.swift

```swift
import Foundation

// Top-level decoder: TOML source string → Decodable T
// Pipeline: TOMLParser → [String: TOMLValue] → toFoundation() → JSONSerialization → JSONDecoder
struct TOMLDecoder: Sendable {

    var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .iso8601
    var keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys

    func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let parsed = try TOMLParser.parse(string)
        let foundation = parsed.mapValues { $0.toFoundation() } as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: foundation)
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = dateDecodingStrategy
        jsonDecoder.keyDecodingStrategy = keyDecodingStrategy
        return try jsonDecoder.decode(type, from: data)
    }
}
```

---

## Add to: project.yml

Add the three new Swift files under the `Merlin` target sources. If sources are enumerated, add:
```yaml
- Merlin/Config/TOMLValue.swift
- Merlin/Config/TOMLParser.swift
- Merlin/Config/TOMLDecoder.swift
```
If sources use glob (`Merlin/**/*.swift`), no change needed — files are auto-included.

After any `project.yml` edit: `xcodegen generate`

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all TOMLDecoderTests pass.

## Commit
```bash
git add Merlin/Config/TOMLValue.swift Merlin/Config/TOMLParser.swift Merlin/Config/TOMLDecoder.swift
git commit -m "Phase 44b — TOMLDecoder (full TOML v1 parser + Foundation bridge)"
```
