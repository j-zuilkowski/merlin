# Phase 330 — Eval Operator Harness (S12–S17)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 329 complete: render harness landed.

W5 — the **M4 operator harness** for the operator/headless scenarios S12–S17. Most of
the operator surface is *integration* by nature — write a config file / drop a trigger
file / define an automation, then launch or drive a running Merlin and observe — and is
executed per the S12–S17 runsheets (FSEvents live-reload, hooks firing mid-loop, the
`inject.txt` poll, cron automations, notification delivery all need a running app).

This phase adds the **deterministic, pure-function operator checks** that *can* be a
fast unit test — the parse/decode layer that, if it regresses, silently breaks every
operator surface above it: MCP config parsing, `${VAR}` env expansion, and the hook-event
set. These run in the `MerlinTests` scheme.

API (verified): `MCPConfig.load(from:) throws -> MCPConfig`;
`MCPServerConfig.expandEnv(_:from:)`; `HookEvent: String, CaseIterable` with 5 cases.

---

## Write to: MerlinTests/Unit/OperatorConfigTests.swift

```swift
import XCTest
@testable import Merlin

/// S12 — operator config, the deterministic parse/decode layer. The live operator
/// behaviours (config.toml FSEvents reload, hooks firing, inject.txt poll, cron
/// automations) are integration and run via the S12–S17 runsheets.
final class OperatorConfigTests: XCTestCase {

    private func writeTemp(_ name: String, _ contents: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("operator-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: - MCP config (S12 §M)

    func testMCPConfigParsesAServerFile() throws {
        let path = try writeTemp("mcp.json", """
        {
          "mcpServers": {
            "demo": {
              "command": "/bin/echo",
              "args": ["hello"],
              "transport": "stdio"
            }
          }
        }
        """)
        defer { try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: path).deletingLastPathComponent()) }

        let config = try MCPConfig.load(from: path)
        let server = config.mcpServers["demo"]
        XCTAssertNotNil(server, "the 'demo' MCP server must parse")
        XCTAssertEqual(server?.command, "/bin/echo")
        XCTAssertEqual(server?.args, ["hello"])
    }

    func testMCPLoadOfAMissingFileIsEmptyNotAnError() throws {
        let config = try MCPConfig.load(from: "/nonexistent/mcp.json")
        XCTAssertTrue(config.mcpServers.isEmpty,
                      "a missing mcp.json must yield an empty config, not throw")
    }

    func testMCPEnvVarExpansionResolvesPlaceholders() {
        var env = ["TOKEN": "${DEMO_TOKEN}", "PLAIN": "literal-value"]
        MCPServerConfig.expandEnv(&env, from: ["DEMO_TOKEN": "resolved-secret"])
        XCTAssertEqual(env["TOKEN"], "resolved-secret",
                       "`${VAR}` must expand from the process environment")
        XCTAssertEqual(env["PLAIN"], "literal-value",
                       "a non-placeholder value must be left untouched")
    }

    func testMCPEnvVarExpansionLeavesUnknownPlaceholdersUnresolved() {
        var env = ["TOKEN": "${NOT_IN_ENV}"]
        MCPServerConfig.expandEnv(&env, from: [:])
        XCTAssertEqual(env["TOKEN"], "${NOT_IN_ENV}",
                       "an unresolved `${VAR}` is left as-is, not blanked")
    }

    // MARK: - Hook events (S12 §L)

    func testHookEventsAreExactlyTheFiveDocumented() {
        let raw = Set(HookEvent.allCases.map(\.rawValue))
        XCTAssertEqual(
            raw,
            ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop", "SessionStart"],
            "the hook-event set drifted — update SURFACE-CENSUS.md §2.2 to match")
    }
}
```

---

## Operator surface NOT covered here (runsheet-driven — S12–S17)

These need a running Merlin and are scored via the scenario runsheets, not this harness:
config.toml FSEvents live-reload; each hook event actually firing mid-loop and its
decision taking effect; `inject.txt` 2-second poll; cron automations firing; provider/
connector auth and key-file `0600` perms (S13); skill/agent file-watch discovery (S14);
memory generation + **secret redaction** (S15 — gating); AppIntents via Shortcuts (S16);
notification delivery + the env guard (S17). Each scenario file is the M4/M5 spec.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/OperatorConfigTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:|warning:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, zero warnings; all `OperatorConfigTests` pass.

## Commit
```
git add MerlinTests/Unit/OperatorConfigTests.swift phases/phase-330-eval-operator-harness.md
git commit -m "Phase 330 — Eval operator harness (S12–S17)"
```
