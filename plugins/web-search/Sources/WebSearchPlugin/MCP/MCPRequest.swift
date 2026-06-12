import Foundation

struct MCPRequest: Decodable {
    var jsonrpc: String?
    var id: JSONValue?
    var method: String
    var params: JSONValue?
}

enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    func foundationValue() -> Any {
        switch self {
        case .string(let value): return value
        case .number(let value):
            let integer = Int(value)
            return Double(integer) == value ? integer : value
        case .bool(let value): return value
        case .null: return NSNull()
        case .object(let value): return value.mapValues { $0.foundationValue() }
        case .array(let value): return value.map { $0.foundationValue() }
        }
    }
}
