import Foundation

actor MCPBridge {
    private var sessions: [String: MCPServerSession] = [:]
    private var registeredToolNames: Set<String> = []

    static func prefixedToolName(server: String, tool: String) -> String {
        "mcp:\(server):\(tool)"
    }

    func start(config: MCPConfig, toolRouter: ToolRouter) async throws {
        for (serverName, serverConfig) in config.mcpServers {
            let expandedConfig = expandEnvironment(in: serverConfig)
            let session = MCPServerSession(name: serverName, config: expandedConfig)
            try await session.launch()
            sessions[serverName] = session

            let tools = try await session.listTools()
            for tool in tools {
                let definition = Self.toolDefinition(serverName: serverName, tool: tool)
                registeredToolNames.insert(definition.function.name)
                await ToolRegistry.shared.register(definition)
                await MainActor.run {
                    toolRouter.registerMCPTool(definition) { arguments in
                        do {
                            return try await self.call(server: serverName,
                                                       tool: tool.name,
                                                       arguments: arguments)
                        } catch {
                            return String(describing: error)
                        }
                    }
                }
            }
        }
    }

    func call(server: String, tool: String, arguments: [String: Any]) async throws -> String {
        guard let session = sessions[server] else {
            throw MCPError.serverNotFound(server)
        }
        return try await session.callTool(name: tool, arguments: arguments)
    }

    func stop() async {
        for session in sessions.values {
            await session.terminate()
        }
        sessions.removeAll()

        for name in registeredToolNames {
            await ToolRegistry.shared.unregister(named: name)
        }
        registeredToolNames.removeAll()
    }

    private func expandEnvironment(in config: MCPServerConfig) -> MCPServerConfig {
        var copy = config
        MCPServerConfig.expandEnv(&copy.env, from: ProcessInfo.processInfo.environment)
        return copy
    }

    private static func toolDefinition(serverName: String, tool: MCPToolDefinition) -> ToolDefinition {
        ToolDefinition(
            function: .init(
                name: prefixedToolName(server: serverName, tool: tool.name),
                description: tool.description,
                parameters: schema(from: tool.inputSchema)
            )
        )
    }

    private static func schema(from object: JSONObject) -> JSONSchema {
        let type = object.fields["type"]?.stringValue ?? "object"
        let properties = object.fields["properties"]?.objectValue?.reduce(into: [String: JSONSchema]()) { result, pair in
            result[pair.key] = schema(from: pair.value)
        }
        let required = object.fields["required"]?.arrayValue?.compactMap(\.stringValue)
        let items = object.fields["items"].flatMap { schema(from: $0) }
        let description = object.fields["description"]?.stringValue
        let enumValues = object.fields["enum"]?.arrayValue?.compactMap(\.stringValue)
        return JSONSchema(
            type: type,
            properties: properties,
            required: required,
            items: items,
            description: description,
            enumValues: enumValues
        )
    }

    private static func schema(from value: JSONValue) -> JSONSchema {
        if let object = value.objectValue {
            var wrapper = JSONObject()
            wrapper.fields = object
            return schema(from: wrapper)
        }

        switch value {
        case .string(let string):
            return JSONSchema(type: string)
        case .number:
            return JSONSchema(type: "number")
        case .bool:
            return JSONSchema(type: "boolean")
        case .null:
            return JSONSchema(type: "null")
        case .array(let values):
            return JSONSchema(
                type: "array",
                items: values.first.map { schema(from: $0) }
            )
        case .object:
            return JSONSchema(type: "object")
        }
    }
}

enum MCPError: Error {
    case serverNotFound(String)
    case invalidResponse(String)
    case processError(String)
}

private final class MCPServerSession: @unchecked Sendable {
    let name: String
    let config: MCPServerConfig

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var nextID: Int = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var buffer = Data()
    private let lock = NSLock()

    init(name: String, config: MCPServerConfig) {
        self.name = name
        self.config = config
    }

    func launch() async throws {
        let proc = Process()
        proc.executableURL = try resolveExecutable(config.command)
        proc.arguments = config.args
        var env = ProcessInfo.processInfo.environment
        for (key, value) in config.env {
            env[key] = value
        }
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()

        try proc.run()

        process = proc
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutHandle?.readabilityHandler = { [weak self] handle in
            self?.consume(data: handle.availableData)
        }

        _ = try await sendRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "clientInfo": ["name": "Merlin", "version": "2.0"],
            "capabilities": [:]
        ])
        _ = try? await sendRequest(method: "notifications/initialized", params: [:])
    }

    func listTools() async throws -> [MCPToolDefinition] {
        let response = try await sendRequest(method: "tools/list", params: [:])
        guard let result = response["result"] as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }
        let data = try JSONSerialization.data(withJSONObject: toolsArray)
        return (try? JSONDecoder().decode([MCPToolDefinition].self, from: data)) ?? []
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let response = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
        if let result = response["result"] as? [String: Any],
           let content = result["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }
        return String(data: (try? JSONSerialization.data(withJSONObject: response)) ?? Data(),
                      encoding: .utf8) ?? ""
    }

    func terminate() {
        stdoutHandle?.readabilityHandler = nil
        process?.terminate()
        process = nil
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = lock.withLock {
            defer { nextID += 1 }
            return nextID
        }

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let line = String(data: data, encoding: .utf8) else {
            throw MCPError.processError("Failed to encode request")
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                pending[id] = continuation
            }
            guard let bytes = (line + "\n").data(using: .utf8) else {
                lock.withLock {
                    pending.removeValue(forKey: id)
                }
                continuation.resume(throwing: MCPError.processError("Failed to encode request line"))
                return
            }
            stdinHandle?.write(bytes)
        }
    }

    private func consume(data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            buffer.append(data)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex...newline]
                buffer = buffer[buffer.index(after: newline)...]
                guard let response = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let id = response["id"] as? Int,
                      let continuation = pending.removeValue(forKey: id) else {
                    continue
                }
                continuation.resume(returning: response)
            }
        }
    }

    private func resolveExecutable(_ command: String) throws -> URL {
        if command.hasPrefix("/") {
            return URL(fileURLWithPath: command)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            throw MCPError.processError("command not found: \(command)")
        }
        return URL(fileURLWithPath: path)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}
