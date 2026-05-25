# Phase 01b — MCP Server Core

## Context
Swift 5.10, macOS 14+, `async`/`await` + actors. No third-party Swift packages.
`SWIFT_STRICT_CONCURRENCY=complete`. Zero warnings, zero errors required.
Working dir: `~/Documents/localProject/merlin/plugins/merlin-kicad-mcp`
Phase 01a complete: failing `MCPServerCoreTests`.

After this phase the server speaks MCP over stdio: it accepts JSON-RPC 2.0 messages,
answers the `initialize` handshake, lists tools (empty for now), and rejects unknown
methods and malformed input with correct JSON-RPC error codes. The tool registry is
phase 02; the manifest resource is phase 03.

---

## Edit

### 1. New file — `Sources/KiCadMCPKit/MCPServer.swift`

The protocol core. `handle(_:)` is the single, fully testable entry point — parse one
message line, dispatch, return the response line (or nil for a notification).

```swift
import Foundation

/// JSON-RPC 2.0 / MCP protocol core. Pure with respect to I/O: a message line in,
/// a response line out. `StdioTransport` pumps real stdin/stdout through it.
actor MCPServer {

    /// MCP protocol revision this server speaks. Must be a revision Merlin's
    /// `MCPBridge` accepts in its `initialize` negotiation.
    static let protocolVersion = "2025-06-18"

    private let serverName: String
    private let serverVersion: String

    init(serverName: String = "merlin-kicad-mcp", serverVersion: String = "0.1.0") {
        self.serverName = serverName
        self.serverVersion = serverVersion
    }

    /// Process one JSON-RPC message line. Returns the response line, or nil when the
    /// message is a notification (no `id`).
    func handle(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        // Parse. A malformed message → JSON-RPC parse error (-32700), id null.
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any] else {
            return errorLine(id: nil, code: -32700, message: "Parse error")
        }

        let id = message["id"]                       // absent ⇒ notification
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        // Notification: process side effects, never reply.
        if id == nil {
            // e.g. "notifications/initialized" — nothing to do yet.
            return nil
        }

        switch method {
        case "initialize":
            return resultLine(id: id, result: initializeResult())
        case "tools/list":
            return resultLine(id: id, result: ["tools": []])
        case "tools/call":
            // Registry arrives in phase 02. Until then no tool exists.
            return errorLine(id: id, code: -32601,
                             message: "No tools registered")
        case "resources/list":
            return resultLine(id: id, result: ["resources": []])
        case "resources/read":
            return errorLine(id: id, code: -32601,
                             message: "No resources registered")
        default:
            return errorLine(id: id, code: -32601,
                             message: "Method not found: \(method)")
        }
    }

    // MARK: - Results

    private func initializeResult() -> [String: Any] {
        [
            "protocolVersion": Self.protocolVersion,
            "capabilities": ["tools": [:], "resources": [:]],
            "serverInfo": ["name": serverName, "version": serverVersion],
        ]
    }

    // MARK: - JSON-RPC encoding

    /// Encodes a success response to a single line (no embedded newlines).
    private func resultLine(id: Any?, result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    /// Encodes an error response to a single line.
    private func errorLine(id: Any?, code: Int, message: String) -> String {
        encode([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message],
        ])
    }

    private func encode(_ object: [String: Any]) -> String {
        // No .prettyPrinted — the message MUST be a single line.
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return string
    }
}
```

JSON-RPC error codes used: `-32700` parse error, `-32601` method not found, `-32603`
internal error. Phase 02 adds `-32602` (invalid params) when tool arguments are bad.

### 2. New file — `Sources/KiCadMCPKit/StdioTransport.swift`

Pumps real stdin/stdout. MCP stdio framing is **newline-delimited JSON** — one message
per line. stderr is free for logging.

```swift
import Foundation

/// Reads newline-delimited JSON-RPC messages from stdin, routes each through an
/// `MCPServer`, and writes responses to stdout. Logging goes to stderr only —
/// stdout carries protocol traffic exclusively.
struct StdioTransport: Sendable {
    let server: MCPServer

    func run() async {
        // Read stdin line by line. For each non-empty line:
        //   if let response = await server.handle(line) {
        //       write response + "\n" to stdout, then flush.
        //   }
        // On EOF, return (the process exits).
        // Use FileHandle.standardInput; accumulate bytes and split on "\n".
        // (Full body written here — block until EOF.)
    }
}
```

Implementation notes for `run()`:
- Read from `FileHandle.standardInput` in chunks; buffer and split on `\n`.
- Each complete line → `await server.handle(line)`; write any response with a trailing
  `\n` to `FileHandle.standardOutput`; do not buffer indefinitely — flush per message.
- Never write logs or diagnostics to stdout — only JSON-RPC response lines. Use
  `FileHandle.standardError` for logging.

### 3. Replace `Sources/merlin-kicad-mcp/main.swift`

```swift
import KiCadMCPKit

await StdioTransport(server: MCPServer()).run()
```

---

## Verify

```bash
swift build 2>&1 | grep -E 'error:|warning:|Build complete' | tail -10
swift test  2>&1 | grep -E 'passed|failed|error:' | tail -20
```

Expected: **Build complete**, all phase 01a `MCPServerCoreTests` pass, `ScaffoldTests`
still passes, zero warnings.

**Manual check:** pipe an initialize request in and confirm a single-line response:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  | swift run merlin-kicad-mcp
```

Expect one line of JSON containing `"serverInfo":{"name":"merlin-kicad-mcp"...}`.

## Commit

```bash
cd ~/Documents/localProject/merlin/plugins/merlin-kicad-mcp
git add Sources/KiCadMCPKit/MCPServer.swift \
    Sources/KiCadMCPKit/StdioTransport.swift \
    Sources/merlin-kicad-mcp/main.swift \
    tasks/task-01b-mcp-server-core.md
git commit -m "kicad-mcp Phase 01b — MCP server core: JSON-RPC over stdio"
```

## Fixes

The server now speaks MCP: JSON-RPC 2.0 over newline-delimited stdio, the `initialize`
handshake, `tools/list` / `resources/list`, and correct error codes for unknown methods
and malformed input. Phase 02 adds the tool registry so `tools/call` dispatches real
work; phase 03 adds the `merlin://domain/manifest` resource.
