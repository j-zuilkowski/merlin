# Task 220a - MCP HTTP/SSE Transport Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Architecture currently says MCP is stdio-only and HTTP/SSE is deferred to v3.

New surface introduced in task 220b:
  - `MCPTransportKind` - `stdio`, `http`, `sse`
  - `MCPHTTPTransport` - JSON-RPC over HTTP POST
  - `MCPSSETransport` - SSE event stream with JSON-RPC message dispatch
  - `MCPServerConfig.transportKind` - parsed from config

TDD coverage:
  File 1 - `MCPHTTPTransportTests`: request encoding, response decoding, non-2xx error handling.
  File 2 - `MCPSSETransportTests`: SSE event parsing, message correlation, stream close handling.
  File 3 - `MCPBridgeTransportSelectionTests`: bridge selects stdio/http/sse from config.

---

## Add: MerlinTests/Unit/MCPHTTPTransportTests.swift

Create tests using a custom `URLProtocol` test double. No network.

Assert:

1. JSON-RPC requests are sent as HTTP POST with `application/json`.
2. JSON-RPC response IDs resolve the matching pending request.
3. HTTP 4xx/5xx responses throw a typed MCP transport error.
4. Malformed JSON responses throw a typed decode error.

---

## Add: MerlinTests/Unit/MCPSSETransportTests.swift

Create tests around a small SSE parser helper. No network.

Assert:

1. `data: {...}\n\n` frames decode into JSON-RPC messages.
2. Multiline `data:` frames are joined with newline separators.
3. Comment/heartbeat lines beginning with `:` are ignored.
4. EOF closes pending requests with a transport-closed error.

---

## Add: MerlinTests/Unit/MCPBridgeTransportSelectionTests.swift

Assert:

1. Config with no transport kind keeps stdio as default.
2. `transport = "http"` creates HTTP transport using the configured URL.
3. `transport = "sse"` creates SSE transport using the configured URL.
4. Unknown transport values fail validation before launch.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because HTTP/SSE MCP transport types do not exist.

## Commit

```bash
git add MerlinTests/Unit/MCPHTTPTransportTests.swift MerlinTests/Unit/MCPSSETransportTests.swift MerlinTests/Unit/MCPBridgeTransportSelectionTests.swift
git commit -m "Task 220a - MCPHTTPTransportTests and MCPSSETransportTests (failing)"
```

