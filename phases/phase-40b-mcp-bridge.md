# Phase 40b — MCPBridge Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 40a complete: failing MCPBridgeTests in place.

MCP stdio transport: Merlin spawns each configured server as a child Process, communicates
over stdin/stdout using JSON-RPC 2.0. Only stdio transport is supported in v2.

---

## Write to: Merlin/MCP/MCPConfig.swift

```swift
import Foundation

struct MCPServerConfig: Codable, Sendable {
    var command: String
    var args: [String]
    var env: [String: String]

    init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.env = env
    }

    enum CodingKeys: String, CodingKey {
        case command, args, env
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        command = try c.decode(String.self, forKey: .command)
        args    = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        env     = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
    }

    /// Expands ${VAR} placeholders in env values using the provided environment dictionary.
    static func expandEnv(_ env: inout [String: String], from processEnv: [String: String]) {
        for key in env.keys {
            if let val = env[key], val.hasPrefix("${"), val.hasSuffix("}") {
                let varName = String(val.dropFirst(2).dropLast())
                if let resolved = processEnv[varName] {
                    env[key] = resolved
                }
                // If not found, leave as-is
            }
        }
    }
}

struct MCPConfig: Codable, Sendable {
    var mcpServers: [String: MCPServerConfig]

    enum CodingKeys: String, CodingKey { case mcpServers }

    /// Load from file path. Returns empty config if file is absent.
    static func load(from path: String) throws -> MCPConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            return MCPConfig(mcpServers: [:])
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(MCPConfig.self, from: data)
    }

    /// Merged config: project-level overrides global.
    static func merged(projectPath: String) -> MCPConfig {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let global  = (try? load(from: "\(home)/.merlin/mcp.json")) ?? MCPConfig(mcpServers: [:])
        let project = (try? load(from: "\(projectPath)/.mcp.json")) ?? MCPConfig(mcpServers: [:])
        var merged = global.mcpServers
        project.mcpServers.forEach { merged[$0.key] = $0.value }
        return MCPConfig(mcpServers: merged)
    }
}
```

---

## Write to: Merlin/MCP/MCPToolDefinition.swift

```swift
import Foundation

struct MCPToolDefinition: Codable, Sendable {
    var name: String
    var description: String
    var inputSchema: JSONObject

    enum CodingKeys: String, CodingKey { case name, description, inputSchema }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name        = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        inputSchema = try c.decodeIfPresent(JSONObject.self, forKey: .inputSchema) ?? JSONObject()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(inputSchema, forKey: .inputSchema)
    }
}

// Lightweight JSON object wrapper — avoids Any and retains Sendable/Codable conformance.
struct JSONObject: Codable, Sendable {
    var fields: [String: JSONValue] = [:]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        fields = (try? c.decode([String: JSONValue].self)) ?? [:]
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(fields)
    }
}

enum JSONValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), null
    case object([String: JSONValue]), array([JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self)               { self = .string(s); return }
        if let n = try? c.decode(Double.self)               { self = .number(n); return }
        if let b = try? c.decode(Bool.self)                 { self = .bool(b);   return }
        if let o = try? c.decode([String: JSONValue].self)  { self = .object(o); return }
        if let a = try? c.decode([JSONValue].self)          { self = .array(a);  return }
        if c.decodeNil()                                    { self = .null;      return }
        throw DecodingError.typeMismatch(JSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .null:          try c.encodeNil()
        case .object(let o): try c.encode(o)
        case .array(let a):  try c.encode(a)
        }
    }
}
```

---

## Write to: Merlin/MCP/MCPBridge.swift

```swift
import Foundation

actor MCPBridge {
    private var processes: [String: MCPProcess] = [:]

    // MARK: - Public API

    static func prefixedToolName(server: String, tool: String) -> String {
        "mcp:\(server):\(tool)"
    }

    /// Start all servers and register their tools into ToolRouter.
    func start(config: MCPConfig, toolRouter: ToolRouter) async throws {
        for (serverName, var serverConfig) in config.mcpServers {
            // Expand env variables
            MCPServerConfig.expandEnv(&serverConfig.env,
                                      from: ProcessInfo.processInfo.environment)
            let proc = MCPProcess(name: serverName, config: serverConfig)
            try await proc.launch()
            processes[serverName] = proc

            // Discover tools
            let tools = try await proc.listTools()
            for tool in tools {
                let prefixedName = MCPBridge.prefixedToolName(server: serverName, tool: tool.name)
                let def = ToolDefinition(
                    name: prefixedName,
                    description: tool.description,
                    parameters: tool.inputSchema
                )
                await MainActor.run {
                    toolRouter.registerMCPTool(def) { [weak self] args in
                        guard let self else { return "MCP bridge deallocated" }
                        return await (try? self.call(server: serverName,
                                                     tool: tool.name,
                                                     arguments: args)) ?? "error: call failed"
                    }
                }
            }
        }
    }

    /// Dispatch a tool call to the named server.
    func call(server: String, tool: String, arguments: [String: Any]) async throws -> String {
        guard let proc = processes[server] else {
            throw MCPError.serverNotFound(server)
        }
        return try await proc.callTool(name: tool, arguments: arguments)
    }

    func stop() async {
        for proc in processes.values { await proc.terminate() }
        processes.removeAll()
    }
}

enum MCPError: Error {
    case serverNotFound(String)
    case invalidResponse(String)
    case processError(String)
}

// MARK: - MCPProcess (stdio JSON-RPC client)

private actor MCPProcess {
    let name: String
    let config: MCPServerConfig
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextID: Int = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var readBuffer = Data()

    init(name: String, config: MCPServerConfig) {
        self.name = name
        self.config = config
    }

    func launch() async throws {
        let proc = Process()
        proc.executableURL = try resolveExecutable(config.command)
        proc.arguments = config.args
        var env = ProcessInfo.processInfo.environment
        config.env.forEach { env[$0.key] = $0.value }
        proc.environment = env

        let inPipe  = Pipe()
        let outPipe = Pipe()
        proc.standardInput  = inPipe
        proc.standardOutput = outPipe
        proc.standardError  = Pipe()

        try proc.run()
        self.process    = proc
        self.stdinPipe  = inPipe
        self.stdoutPipe = outPipe

        // Start reading stdout in background
        Task { await self.readLoop() }

        // MCP initialization handshake
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
            "name": name, "arguments": arguments
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
        process?.terminate()
        process = nil
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextID; nextID += 1
        let req: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: req)
        let line = String(data: data, encoding: .utf8)! + "\n"
        stdinPipe?.fileHandleForWriting.write(line.data(using: .utf8)!)

        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
        }.flatMap { data -> [String: Any] in
            (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } ?? [:]
    }

    private func readLoop() async {
        guard let handle = stdoutPipe?.fileHandleForReading else { return }
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            readBuffer += chunk
            processBuffer()
        }
    }

    private func processBuffer() {
        while let newline = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = readBuffer[readBuffer.startIndex...newline]
            readBuffer = readBuffer[readBuffer.index(after: newline)...]
            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let id = json["id"] as? Int,
               let cont = pending.removeValue(forKey: id) {
                cont.resume(returning: lineData)
            }
        }
    }

    private func resolveExecutable(_ command: String) throws -> URL {
        if command.hasPrefix("/") { return URL(fileURLWithPath: command) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { throw MCPError.processError("command not found: \(command)") }
        return URL(fileURLWithPath: path)
    }
}

// Convenience — avoid force-casting the continuation result
private extension CheckedContinuation where T == Data, E == Error {
    func flatMap<U>(_ transform: (Data) throws -> U) rethrows -> U? {
        nil // This extension is unused; sendRequest uses a different pattern
    }
}
```

Note: `sendRequest` returns `[String: Any]` directly. Revise the continuation resume
to decode the full JSON-RPC response inline — adjust `pending` type to
`[Int: CheckedContinuation<[String: Any], Error>]` and decode in `processBuffer`.

---

## Modify: Merlin/Engine/ToolRouter.swift

Add `registerMCPTool` method:

```swift
func registerMCPTool(_ def: ToolDefinition, handler: @escaping ([String: Any]) async -> String) {
    // Store the handler keyed by tool name; dispatch in the existing dispatch() method
    mcpHandlers[def.name] = handler
    mcpDefinitions.append(def)
}

private var mcpHandlers: [String: ([String: Any]) async -> String] = [:]
private var mcpDefinitions: [ToolDefinition] = []
```

In `dispatch(call:)`, check `mcpHandlers[name]` before native tool dispatch.

Also add `mcpDefinitions` to the list of tool definitions returned to the provider.

---

## Modify: Merlin/Sessions/LiveSession.swift

Start the `MCPBridge` at session creation:

```swift
let mcpBridge = MCPBridge()

init(projectRef: ProjectRef) {
    // ... existing init
    Task {
        let config = MCPConfig.merged(projectPath: projectRef.path)
        try? await mcpBridge.start(config: config,
                                   toolRouter: self.appState.engine.toolRouter)
    }
}
```

---

## Modify: project.yml

Add to Merlin target sources:
- `Merlin/MCP/MCPConfig.swift`
- `Merlin/MCP/MCPToolDefinition.swift`
- `Merlin/MCP/MCPBridge.swift`

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `MCPBridgeTests` → 9 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/MCP/MCPConfig.swift \
        Merlin/MCP/MCPToolDefinition.swift \
        Merlin/MCP/MCPBridge.swift \
        Merlin/Engine/ToolRouter.swift \
        Merlin/Sessions/LiveSession.swift \
        project.yml
git commit -m "Phase 40b — MCPBridge: stdio transport + tool registration"
```
