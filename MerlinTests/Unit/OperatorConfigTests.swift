import XCTest
@testable import Merlin

/// S12 - operator config, the deterministic parse/decode layer. The live operator
/// behaviours (config.toml FSEvents reload, hooks firing, inject.txt poll, cron
/// automations) are integration and run via the S12-S17 runsheets.
final class OperatorConfigTests: XCTestCase {

    private func writeTemp(_ name: String, _ contents: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("operator-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: - MCP config (S12 M)

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

    func testMCPMergedConfigResolvesProjectRootPlaceholders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("operator-project-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        {
          "mcpServers": {
            "web-search": {
              "command": "/usr/bin/swift",
              "args": ["run", "--package-path", "${MERLIN_PROJECT_ROOT}/plugins/web-search", "web-search-plugin"],
              "env": {
                "PLUGIN_ROOT": "${MERLIN_PROJECT_ROOT}/plugins/web-search"
              }
            }
          }
        }
        """.write(to: root.appendingPathComponent(".mcp.json"), atomically: true, encoding: .utf8)

        let config = MCPConfig.merged(projectPath: root.path)
        let server = try XCTUnwrap(config.mcpServers["web-search"])
        XCTAssertEqual(server.args[2], root.appendingPathComponent("plugins/web-search").path)
        XCTAssertEqual(server.env["PLUGIN_ROOT"], root.appendingPathComponent("plugins/web-search").path)
    }

    // MARK: - Hook events (S12 L)

    func testHookEventsAreExactlyTheFiveDocumented() {
        let raw = Set(HookEvent.allCases.map(\.rawValue))
        XCTAssertEqual(
            raw,
            ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop", "SessionStart"],
            "the hook-event set drifted - update SURFACE-CENSUS.md section 2.2 to match")
    }
}
