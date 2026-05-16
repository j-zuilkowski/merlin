# Phase 01a — MCP Server Core Tests (failing)

## Context
Swift 5.10, macOS 14+, `async`/`await` + actors. No third-party Swift packages.
`SWIFT_STRICT_CONCURRENCY=complete`. Zero warnings, zero errors required.
Working dir: `~/Documents/localProject/merlin/plugins/merlin-kicad-mcp`
Phase 00 complete: Swift package scaffold (`KiCadMCPKit` library + executable + test
target) builds and `ScaffoldTests` passes.

This phase covers the MCP protocol core: JSON-RPC 2.0 message handling and the MCP
lifecycle (`initialize`, `tools/list`, etc.). The tool *registry* is phase 02 — here
`tools/list` returns an empty array and unknown methods return method-not-found.

The protocol logic is kept pure and testable: `MCPServer.handle(_:)` takes one
newline-delimited JSON-RPC message string and returns the response string (or nil for a
notification). The stdio pump (`StdioTransport`) is built in phase 01b and exercised by
the manual check, not unit tests — all protocol behaviour is tested through `handle`.

New surface introduced in phase 01b:
  - `MCPServer` actor in `Sources/KiCadMCPKit/MCPServer.swift`:
    ```swift
    actor MCPServer {
        init(serverName: String = "merlin-kicad-mcp", serverVersion: String = "0.1.0")
        /// Process one JSON-RPC message line. Returns the response line, or nil when
        /// the message is a notification (no `id`) and no response is sent.
        func handle(_ line: String) async -> String?
    }
    ```
  - `StdioTransport` in `Sources/KiCadMCPKit/StdioTransport.swift` — pumps stdin lines
    through an `MCPServer` and writes responses to stdout (newline-delimited).

TDD coverage:
  File 1 — `Tests/KiCadMCPKitTests/MCPServerCoreTests.swift`: `initialize` returns
    `serverInfo` / `protocolVersion` / `capabilities`; responses echo the request `id`;
    `tools/list` returns a `tools` array; an unknown method returns JSON-RPC error
    `-32601`; malformed JSON returns `-32700`; a notification produces no response.

---

## Write to: Tests/KiCadMCPKitTests/MCPServerCoreTests.swift

```swift
import XCTest
@testable import KiCadMCPKit

final class MCPServerCoreTests: XCTestCase {

    private func handle(_ line: String) async -> String? {
        await MCPServer().handle(line)
    }

    /// Parse a JSON-RPC response line into a dictionary.
    private func object(_ line: String?) throws -> [String: Any] {
        let data = try XCTUnwrap(line?.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInitializeReturnsServerInfo() async throws {
        let req = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#
        let resp = try object(await handle(req))
        XCTAssertEqual(resp["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(resp["id"] as? Int, 1)
        let result = try XCTUnwrap(resp["result"] as? [String: Any])
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "merlin-kicad-mcp")
        XCTAssertNotNil(result["protocolVersion"])
        XCTAssertNotNil(result["capabilities"])
    }

    func testResponseEchoesRequestID() async throws {
        let req = #"{"jsonrpc":"2.0","id":42,"method":"tools/list","params":{}}"#
        let resp = try object(await handle(req))
        XCTAssertEqual(resp["id"] as? Int, 42)
    }

    func testToolsListReturnsAToolsArray() async throws {
        let req = #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#
        let resp = try object(await handle(req))
        let result = try XCTUnwrap(resp["result"] as? [String: Any])
        XCTAssertNotNil(result["tools"] as? [Any],
                        "tools/list must return a 'tools' array (empty until phase 02)")
    }

    func testUnknownMethodReturnsMethodNotFound() async throws {
        let req = #"{"jsonrpc":"2.0","id":3,"method":"no/such/method","params":{}}"#
        let resp = try object(await handle(req))
        let error = try XCTUnwrap(resp["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    func testMalformedJSONReturnsParseError() async throws {
        let resp = try object(await handle("{not valid json"))
        let error = try XCTUnwrap(resp["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32700)
    }

    func testNotificationProducesNoResponse() async {
        // A JSON-RPC message with no "id" is a notification — the server must not reply.
        let note = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let resp = await handle(note)
        XCTAssertNil(resp, "a notification must not produce a response line")
    }
}
```

---

## Verify

```bash
swift build 2>&1 | grep -E 'error:|warning:|Build complete' | tail -10
```

Expected: **build fails** — `MCPServer` is undefined. That is the TDD signal.

## Commit

```bash
cd ~/Documents/localProject/merlin/plugins/merlin-kicad-mcp
git add Tests/KiCadMCPKitTests/MCPServerCoreTests.swift phases/phase-01a-mcp-server-core-tests.md
git commit -m "kicad-mcp Phase 01a — MCPServerCoreTests (failing)"
```
