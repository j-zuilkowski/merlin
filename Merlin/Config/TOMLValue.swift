import Foundation

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
    func toFoundation() -> Any {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return value
        case .float(let value):
            return value
        case .bool(let value):
            return value
        case .datetime(let value):
            return ISO8601DateFormatter().string(from: value)
        case .array(let values):
            return values.map { $0.toFoundation() }
        case .table(let values):
            return values.mapValues { $0.toFoundation() }
        }
    }
}

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
        case .unexpectedToken(let value):
            return "Unexpected token: \(value)"
        case .duplicateKey(let key):
            return "Duplicate key: \(key)"
        case .keyRedefinition(let key):
            return "Key redefined as different type: \(key)"
        case .unterminatedString:
            return "Unterminated string"
        case .invalidEscape(let value):
            return "Invalid escape: \\\(value)"
        case .invalidUnicodeScalar(let value):
            return "Invalid Unicode scalar: \(value)"
        case .invalidValue(let value):
            return "Invalid value: \(value)"
        case .invalidDatetime(let value):
            return "Invalid datetime: \(value)"
        case .arrayTypeMismatch:
            return "Mixed types in array"
        }
    }
}
