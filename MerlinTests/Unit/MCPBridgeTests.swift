import XCTest
@testable import Merlin

final class MCPBridgeTests: XCTestCase {

    // MARK: - MCPServerConfig parsing

    func testMCPConfigRoundTrip() throws {
        let json = """
        {
          "mcpServers": {
            "github": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-github"],
              "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}" }
            }
          }
        }
        """
        let config = try JSONDecoder().decode(MCPConfig.self,
                                              from: Data(json.utf8))
        let server = config.mcpServers["github"]
        XCTAssertNotNil(server)
        XCTAssertEqual(server?.command, "npx")
        XCTAssertEqual(server?.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(server?.env["GITHUB_PERSONAL_ACCESS_TOKEN"], "${GITHUB_TOKEN}")
    }

    func testMCPConfigWithNoServersDecodesEmpty() throws {
        let json = #"{"mcpServers": {}}"#
        let config = try JSONDecoder().decode(MCPConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.mcpServers.isEmpty)
    }

    func testMCPConfigMissingFieldsDecodesToDefaults() throws {
        let json = #"{"mcpServers": {"minimal": {"command": "echo", "args": []}}}"#
        let config = try JSONDecoder().decode(MCPConfig.self, from: Data(json.utf8))
        let server = config.mcpServers["minimal"]
        XCTAssertEqual(server?.command, "echo")
        XCTAssertTrue(server?.env.isEmpty ?? true)
    }

    // MARK: - Environment variable expansion

    func testEnvVarExpansionReplacesPlaceholder() {
        var env = ["TOKEN": "${MY_TOKEN}"]
        let processEnv = ["MY_TOKEN": "secret123"]
        MCPServerConfig.expandEnv(&env, from: processEnv)
        XCTAssertEqual(env["TOKEN"], "secret123")
    }

    func testEnvVarExpansionLeavesLiteralUnchanged() {
        var env = ["TOKEN": "literal-value"]
        MCPServerConfig.expandEnv(&env, from: ["TOKEN": "should-not-apply"])
        XCTAssertEqual(env["TOKEN"], "literal-value")
    }

    func testEnvVarExpansionLeavsMissingVarAsIs() {
        var env = ["TOKEN": "${UNDEFINED_VAR}"]
        MCPServerConfig.expandEnv(&env, from: [:])
        XCTAssertEqual(env["TOKEN"], "${UNDEFINED_VAR}",
                       "Undefined env vars must be left as-is, not replaced with empty string")
    }

    // MARK: - Tool name prefixing

    func testToolNameIsPrefixedWithMCPServerName() {
        let toolName = MCPBridge.prefixedToolName(server: "github", tool: "list_pull_requests")
        XCTAssertEqual(toolName, "mcp:github:list_pull_requests")
    }

    // MARK: - MCPToolDefinition parsing

    func testMCPToolDefinitionParsesNameAndDescription() throws {
        let json = """
        {
          "name": "list_issues",
          "description": "List GitHub issues for a repository",
          "inputSchema": {
            "type": "object",
            "properties": {
              "repo": { "type": "string" }
            }
          }
        }
        """
        let def = try JSONDecoder().decode(MCPToolDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(def.name, "list_issues")
        XCTAssertEqual(def.description, "List GitHub issues for a repository")
    }

    // MARK: - Config loading

    func testLoadConfigFromFile() throws {
        let tmpPath = "/tmp/mcp-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }
        let json = #"{"mcpServers": {"test": {"command": "cat", "args": []}}}"#
        try json.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        let config = try MCPConfig.load(from: tmpPath)
        XCTAssertNotNil(config.mcpServers["test"])
    }

    func testLoadConfigMissingFileReturnsEmpty() throws {
        let config = try MCPConfig.load(from: "/tmp/nonexistent-mcp.json")
        XCTAssertTrue(config.mcpServers.isEmpty)
    }
}
