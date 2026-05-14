# Phase 220b - MCP HTTP/SSE Transport

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 220a complete: failing MCP HTTP/SSE transport tests exist.

---

## Add: Merlin/MCP/MCPHTTPTransport.swift

Implement JSON-RPC over HTTP POST using `URLSession`.

Rules:

1. No third-party packages.
2. Preserve existing OpenAI function-calling tool definitions.
3. Keep request/response correlation behavior aligned with the stdio bridge.
4. Surface non-2xx, malformed JSON, and closed transport as typed errors.

---

## Add: Merlin/MCP/MCPSSETransport.swift

Implement an SSE frame parser and transport wrapper.

Rules:

1. Parse `data:` frames only.
2. Ignore SSE comments and heartbeats.
3. Support multiline `data:` frames.
4. Close pending continuations if the stream ends.

---

## Edit: Merlin/MCP/MCPBridge.swift

Add transport selection from `MCPServerConfig.transportKind`.

Default remains stdio so existing configs continue to work.

---

## Edit: Merlin/Config/AppSettings.swift

Persist/parse MCP transport kind and URL fields if MCP server config is modeled there.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. New MCP transport tests pass.

## Commit

```bash
git add Merlin/MCP/MCPHTTPTransport.swift Merlin/MCP/MCPSSETransport.swift Merlin/MCP/MCPBridge.swift Merlin/Config/AppSettings.swift MerlinTests/Unit/MCPHTTPTransportTests.swift MerlinTests/Unit/MCPSSETransportTests.swift MerlinTests/Unit/MCPBridgeTransportSelectionTests.swift
git commit -m "Phase 220b - MCP HTTP and SSE transports"
```

## Fixes

**MCPHTTPTransport — JSON decode errors now wrapped in typed error.**

`MCPHTTPTransport.call()` passed `JSONSerialization.jsonObject(with:)` through with
`try`, letting a raw `NSCocoaErrorDomain` error escape when the response body is
malformed JSON. Callers expecting `MCPTransportError` had to catch both `MCPTransportError`
and arbitrary Foundation errors. Added a `do/catch` around the deserialisation call that
re-throws as `MCPTransportError.decodeError(error.localizedDescription)`, keeping the
transport's error boundary clean.

**MCPSSETransportTests — raw string literal syntax bug corrected.**

`test_parser_joinsMultilineDataFrames` used `#"...\n..."#` (a raw string literal where
`\n` is two characters, backslash + n) to assert the joined output. The parser uses
`joined(separator: "\n")` which produces a real newline (U+000A), as required by
RFC 8895 §9.2. Changed the expected value to a regular string literal
`"...\n..."` so `\n` is interpreted as a real newline.

