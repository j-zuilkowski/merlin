import Foundation

struct MCPToolDefinition: Codable, Sendable {
    var name: String
    var description: String
    var inputSchema: JSONObject

    enum CodingKeys: String, CodingKey { case name, description, inputSchema }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        inputSchema = try container.decodeIfPresent(JSONObject.self, forKey: .inputSchema) ?? JSONObject()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
    }
}

struct JSONObject: Codable, Sendable {
    var fields: [String: JSONValue] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        fields = (try? container.decode([String: JSONValue].self)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }
}

enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }
}
