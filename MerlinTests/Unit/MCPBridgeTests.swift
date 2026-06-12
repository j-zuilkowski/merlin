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

    @MainActor
    func testRealKiCadServerRegistersManifestBackedElectronicsDomain() async throws {
        let pluginID = "mcp:kicad:kicad"
        await DomainRegistry.shared.unregister(id: pluginID)

        let memory = AuthMemory(storePath: "/tmp/auth-mcp-bridge-domain-integration.json")
        let router = ToolRouter(authGate: AuthGate(memory: memory, presenter: NullAuthPresenter()))
        let bridge = MCPBridge()

        let config = MCPConfig(mcpServers: [
            "kicad": MCPServerConfig(
                command: Self.kicadRunScriptPath,
                transportKind: .stdio
            )
        ])

        try await bridge.start(config: config, toolRouter: router)

        let plugin = await DomainRegistry.shared.plugin(for: pluginID)
        XCTAssertNotNil(plugin)
        XCTAssertEqual(plugin?.canonicalDomainID, ElectronicsDomain.defaultID)
        XCTAssertEqual(plugin?.displayName, "Electronics (KiCad MCP)")
        XCTAssertFalse(plugin?.isUserSelectable ?? true)
        XCTAssertTrue(plugin?.mcpToolNames.contains("mcp:kicad:kicad_check_version") == true)

        let softwareScoped = router.mcpToolDefinitions(activeDomainIDs: SoftwareDomain.defaultActiveDomainIDs)
            .map(\.function.name)
        XCTAssertFalse(softwareScoped.contains("mcp:kicad:kicad_check_version"))

        let electronicsScoped = router.mcpToolDefinitions(
            activeDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        ).map(\.function.name)
        XCTAssertTrue(electronicsScoped.contains("mcp:kicad:kicad_check_version"))

        await bridge.stop(toolRouter: router)
        await DomainRegistry.shared.unregister(id: pluginID)
    }

    @MainActor
    func testTier2PluginManifestRegistersSettingsCapabilitiesAndAliasRoute() async throws {
        let runtime = try makeRuntime()
        let router = makeRouter(runtime: runtime)
        router.permissionMode = .autoAccept
        let bridge = MCPBridge(sessionFactory: { _, _ in
            FakeMCPTransportSession(
                tools: [Self.webSearchTool()],
                resources: ["merlin://plugin/manifest": Self.webSearchManifest()]
            )
        })

        try await bridge.start(config: fakeConfig(), toolRouter: router)

        let schemas = await runtime.bus.registeredSettingsSchemas()
        XCTAssertTrue(schemas.contains { $0.namespace == "plugin.web_search" })
        let capabilities = await runtime.bus.registeredCapabilities()
        XCTAssertTrue(capabilities.contains {
            $0.address == WorkspaceMessageAddress(namespace: "plugin.web_search", capability: "search")
        })
        XCTAssertEqual(
            router.route(for: "web_search")?.address,
            WorkspaceMessageAddress(namespace: "plugin.web_search", capability: "search")
        )
        XCTAssertEqual(
            router.route(for: "mcp:web-search:web_search")?.address,
            WorkspaceMessageAddress(namespace: "plugin.web_search", capability: "search")
        )

        let result = await router.dispatch([ToolCall(
            id: "call-1",
            type: "function",
            function: FunctionCall(name: "web_search", arguments: #"{"query":"merlin"}"#)
        )]).first

        XCTAssertEqual(result?.content, "called:web_search")
        XCTAssertFalse(result?.isError ?? true)

        await bridge.stop(toolRouter: router)
    }

    @MainActor
    func testTier2ManifestAbsentKeepsExistingMCPToolBehavior() async throws {
        let runtime = try makeRuntime()
        let router = makeRouter(runtime: runtime)
        let bridge = MCPBridge(sessionFactory: { _, _ in
            FakeMCPTransportSession(tools: [Self.echoTool()], resources: [:])
        })

        try await bridge.start(config: fakeConfig(serverName: "plain"), toolRouter: router)

        let schemas = await runtime.bus.registeredSettingsSchemas()
        XCTAssertTrue(schemas.isEmpty)
        XCTAssertNil(router.route(for: "echo"))
        XCTAssertEqual(router.route(for: "mcp:plain:echo")?.address.namespace, "mcp.plain")

        await bridge.stop(toolRouter: router)
    }

    @MainActor
    func testTier2PluginManifestUnloadRemovesSettingsAndTools() async throws {
        let runtime = try makeRuntime()
        let router = makeRouter(runtime: runtime)
        let bridge = MCPBridge(sessionFactory: { _, _ in
            FakeMCPTransportSession(
                tools: [Self.webSearchTool()],
                resources: ["merlin://plugin/manifest": Self.webSearchManifest()]
            )
        })

        try await bridge.start(config: fakeConfig(), toolRouter: router)
        await bridge.stop(toolRouter: router)

        let schemas = await runtime.bus.registeredSettingsSchemas()
        let capabilities = await runtime.bus.registeredCapabilities()
        XCTAssertFalse(schemas.contains { $0.namespace == "plugin.web_search" })
        XCTAssertFalse(capabilities.contains {
            $0.address == WorkspaceMessageAddress(namespace: "plugin.web_search", capability: "search")
        })
        XCTAssertNil(router.route(for: "web_search"))
        XCTAssertNil(router.route(for: "mcp:web-search:web_search"))
        XCTAssertFalse(ToolRegistry.shared.contains(named: "web_search"))
        XCTAssertFalse(ToolRegistry.shared.contains(named: "mcp:web-search:web_search"))
    }

    @MainActor
    func testTier2PluginManifestAliasConflictKeepsRawMCPNameOnly() async throws {
        let runtime = try makeRuntime()
        let router = makeRouter(runtime: runtime)
        router.register(name: "web_search", namespace: "builtin.test", capability: "web_search", requiredScope: .readOnly) { _ in
            "existing"
        }
        let bridge = MCPBridge(sessionFactory: { _, _ in
            FakeMCPTransportSession(
                tools: [Self.webSearchTool()],
                resources: ["merlin://plugin/manifest": Self.webSearchManifest()]
            )
        })

        try await bridge.start(config: fakeConfig(), toolRouter: router)

        XCTAssertEqual(router.route(for: "web_search")?.address.namespace, "builtin.test")
        XCTAssertEqual(
            router.route(for: "mcp:web-search:web_search")?.address,
            WorkspaceMessageAddress(namespace: "plugin.web_search", capability: "search")
        )
        XCTAssertFalse(router.mcpToolDefinitions().contains { $0.function.name == "web_search" })

        await bridge.stop(toolRouter: router)
    }

    private static var kicadRunScriptPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Unit
            .deletingLastPathComponent() // MerlinTests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("archive/legacy-merlin-kicad-mcp/run")
            .path
    }

    @MainActor
    private func makeRuntime() throws -> WorkspaceRuntime {
        try WorkspaceRuntime(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-tier2-plugin-root-\(UUID().uuidString)"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-tier2-plugin-home-\(UUID().uuidString)")
        )
    }

    @MainActor
    private func makeRouter(runtime: WorkspaceRuntime) -> ToolRouter {
        ToolRouter(
            authGate: AuthGate(memory: AuthMemory(storePath: "/dev/null"), presenter: NullAuthPresenter()),
            workspaceRuntime: runtime
        )
    }

    private func fakeConfig(serverName: String = "web-search") -> MCPConfig {
        MCPConfig(mcpServers: [
            serverName: MCPServerConfig(command: "fake", transportKind: .stdio)
        ])
    }

    private static func webSearchTool() -> MCPToolDefinition {
        decodeTool("""
        {
          "name": "web_search",
          "description": "Search the web",
          "inputSchema": {
            "type": "object",
            "properties": {
              "query": { "type": "string" }
            },
            "required": ["query"]
          }
        }
        """)
    }

    private static func echoTool() -> MCPToolDefinition {
        decodeTool(#"{"name":"echo","description":"Echo","inputSchema":{"type":"object"}}"#)
    }

    private static func decodeTool(_ json: String) -> MCPToolDefinition {
        try! JSONDecoder().decode(MCPToolDefinition.self, from: Data(json.utf8))
    }

    private static func webSearchManifest() -> String {
        """
        {
          "id": "web-search",
          "display_name": "Web Search",
          "version": "1.0.0",
          "trust_tier": "tier2",
          "enabled": true,
          "domain_ids": [],
          "settings_schema": {
            "namespace": "plugin.web_search",
            "title": "Web Search",
            "fields": []
          },
          "capabilities": [
            {
              "id": "plugin.web_search.search",
              "displayName": "Web Search",
              "kind": "tool",
              "address": {
                "namespace": "plugin.web_search",
                "capability": "search"
              },
              "requiredPermissionScope": "externalSideEffect"
            }
          ],
          "tool_routes": [
            {
              "tool_name": "web_search",
              "stable_alias": "web_search",
              "address": {
                "namespace": "plugin.web_search",
                "capability": "search"
              },
              "required_permission_scope": "externalSideEffect"
            }
          ]
        }
        """
    }
}

private final class FakeMCPTransportSession: MCPTransportSession, @unchecked Sendable {
    private let tools: [MCPToolDefinition]
    private let resources: [String: String]

    init(tools: [MCPToolDefinition], resources: [String: String]) {
        self.tools = tools
        self.resources = resources
    }

    func launch() async throws {}

    func terminate() async {}

    func call(method: String, params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "tools/list":
            let data = try JSONEncoder().encode(tools)
            return [
                "tools": try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            ]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            return ["content": [["type": "text", "text": "called:\(name)"]]]
        case "resources/read":
            guard let uri = params["uri"] as? String,
                  let text = resources[uri] else {
                return ["contents": []]
            }
            return ["contents": [["uri": uri, "text": text]]]
        default:
            return [:]
        }
    }
}
