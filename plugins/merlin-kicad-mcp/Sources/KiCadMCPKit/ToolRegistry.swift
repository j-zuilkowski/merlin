import Foundation

/// One MCP tool: an OpenAI-function-calling-format definition (`name`, `description`,
/// `inputSchema`) plus an async handler. The handler receives the call's `arguments`
/// object as a JSON string and returns a result text payload (typically JSON).
struct MCPTool: Sendable {
    let name: String
    let description: String
    /// The JSON Schema for `arguments`, stored as a JSON object string so the value
    /// stays `Sendable`. `MCPServer` re-parses it when answering `tools/list`.
    let inputSchemaJSON: String
    let handler: @Sendable (String) async -> String
}

/// Decodes a tool call's argument JSON into a dictionary. Pure helper shared by tool
/// handlers — keeps `[String: Any]` out of stored, boundary-crossing state.
enum ToolArguments {
    static func decode(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    static func string(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
    }

    static func int(_ args: [String: Any], _ key: String) -> Int? {
        if let i = args[key] as? Int { return i }
        if let d = args[key] as? Double { return Int(d) }
        if let s = args[key] as? String { return Int(s) }
        return nil
    }
}
