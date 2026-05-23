import Foundation

/// JSON-RPC 2.0 / MCP protocol core. Pure with respect to I/O: a message line in,
/// a response line out. `StdioTransport` pumps real stdin/stdout through it.
///
/// MCP lifecycle: `initialize` handshake, `tools/list`, `tools/call`, `resources/list`.
/// The KiCad tool surface is supplied at init from `KiCadTools.all`.
public actor MCPServer {
    private static let domainManifestURI = "merlin://domain/manifest"

    /// MCP protocol revision this server reports. Merlin's `MCPBridge` sends
    /// `2024-11-05` and does not renegotiate, so this server echoes that revision.
    static let protocolVersion = "2024-11-05"

    private let serverName: String
    private let serverVersion: String
    private let tools: [String: MCPTool]
    private let toolOrder: [String]

    /// The default KiCad server configuration — every `kicad_*` tool registered.
    public init() {
        self.init(serverName: "merlin-kicad-mcp", serverVersion: "0.1.0", tools: KiCadTools.all)
    }

    init(serverName: String = "merlin-kicad-mcp",
         serverVersion: String = "0.1.0",
         tools: [MCPTool] = KiCadTools.all) {
        self.serverName = serverName
        self.serverVersion = serverVersion
        var map: [String: MCPTool] = [:]
        for tool in tools { map[tool.name] = tool }
        self.tools = map
        self.toolOrder = tools.map(\.name)
    }

    /// Process one JSON-RPC message line. Returns the response line, or nil when the
    /// message is a notification (no `id`) and no response is sent.
    func handle(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any] else {
            return errorLine(id: nil, code: -32700, message: "Parse error")
        }

        let id = message["id"]                       // absent ⇒ notification
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        // A true notification (no id) is processed for side effects only.
        if id == nil {
            return nil
        }

        switch method {
        case "initialize":
            return resultLine(id: id, result: initializeResult())
        case "notifications/initialized", "ping":
            return resultLine(id: id, result: [:])
        case "tools/list":
            return resultLine(id: id, result: ["tools": toolListPayload()])
        case "tools/call":
            return await handleToolCall(id: id, params: params)
        case "resources/list":
            return resultLine(id: id, result: ["resources": resourceListPayload()])
        case "resources/read":
            return handleResourceRead(id: id, params: params)
        default:
            return errorLine(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - tools/call

    private func handleToolCall(id: Any?, params: [String: Any]) async -> String {
        guard let name = params["name"] as? String else {
            return errorLine(id: id, code: -32602, message: "Missing tool name")
        }
        guard let tool = tools[name] else {
            return errorLine(id: id, code: -32601, message: "Tool not found: \(name)")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let argumentsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: arguments),
           let string = String(data: data, encoding: .utf8) {
            argumentsJSON = string
        } else {
            argumentsJSON = "{}"
        }
        let text = await tool.handler(argumentsJSON)
        return resultLine(id: id, result: [
            "content": [["type": "text", "text": text]],
            "isError": false,
        ])
    }

    // MARK: - Results

    private func initializeResult() -> [String: Any] {
        [
            "protocolVersion": Self.protocolVersion,
            "capabilities": ["tools": [:], "resources": [:]],
            "serverInfo": ["name": serverName, "version": serverVersion],
        ]
    }

    private func toolListPayload() -> [[String: Any]] {
        toolOrder.compactMap { name -> [String: Any]? in
            guard let tool = tools[name] else { return nil }
            let schema: Any
            if let data = tool.inputSchemaJSON.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                schema = object
            } else {
                schema = ["type": "object"]
            }
            return [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": schema,
            ]
        }
    }

    private func resourceListPayload() -> [[String: Any]] {
        [[
            "uri": Self.domainManifestURI,
            "name": "KiCad domain manifest",
            "description": "Merlin Electronics/KiCad domain manifest.",
            "mimeType": "application/json",
        ]]
    }

    private func handleResourceRead(id: Any?, params: [String: Any]) -> String {
        guard let uri = params["uri"] as? String, uri.isEmpty == false else {
            return errorLine(id: id, code: -32602, message: "Missing resource uri")
        }
        guard uri == Self.domainManifestURI else {
            return errorLine(id: id, code: -32601, message: "Resource not found: \(uri)")
        }
        return resultLine(id: id, result: [
            "contents": [[
                "uri": Self.domainManifestURI,
                "mimeType": "application/json",
                "text": Self.domainManifestJSON(toolNames: toolOrder),
            ]]
        ])
    }

    private static func domainManifestJSON(toolNames: [String]) -> String {
        let manifest: [String: Any] = [
            "id": "kicad",
            "displayName": "Electronics (KiCad MCP)",
            "taskTypes": [
                ["domainID": "kicad", "name": "schematic_design", "displayName": "Schematic Design"],
                ["domainID": "kicad", "name": "pcb_layout", "displayName": "PCB Layout"],
                ["domainID": "kicad", "name": "component_selection", "displayName": "Component Selection"],
                ["domainID": "kicad", "name": "simulation", "displayName": "Simulation"],
                ["domainID": "kicad", "name": "verification", "displayName": "Verification"],
                ["domainID": "kicad", "name": "manufacturing_release", "displayName": "Manufacturing Release"],
            ],
            "highStakesKeywords": [
                "kicad", "pcb", "schematic", "footprint", "gerber", "bom",
                "netlist", "board house", "fabrication", "spice",
            ],
            "systemPromptAddendum": """
            Active domain extension: KiCad MCP. Use the `mcp:kicad:*` tool family for \
            schematic capture, PCB layout, routing, verification, simulation, and \
            fabrication artifacts. Do not hand-author KiCad domain files when these \
            MCP tools are available.
            """,
            "mcpToolNames": toolNames,
            "verificationCommands": [:],
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ), let json = String(data: data, encoding: .utf8) else {
            return #"{"id":"kicad","displayName":"Electronics (KiCad MCP)","taskTypes":[],"highStakesKeywords":[],"mcpToolNames":[],"verificationCommands":{}}"#
        }
        return json
    }

    // MARK: - JSON-RPC encoding

    private func resultLine(id: Any?, result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func errorLine(id: Any?, code: Int, message: String) -> String {
        encode([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message],
        ])
    }

    private func encode(_ object: [String: Any]) -> String {
        // No .prettyPrinted — an MCP stdio message MUST be a single line.
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return string
    }
}
