import XCTest
@testable import Merlin

@MainActor
final class MCPBridgeWebSearchPluginIntegrationTests: XCTestCase {
    func testMCPBridgeLaunchesLocalWebSearchPluginAndRegistersManifestRoutes() async throws {
        let runtime = try WorkspaceRuntime(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-web-search-plugin-root-\(UUID().uuidString)"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-web-search-plugin-home-\(UUID().uuidString)")
        )
        let router = ToolRouter(
            authGate: AuthGate(memory: AuthMemory(storePath: "/dev/null"), presenter: NullAuthPresenter()),
            workspaceRuntime: runtime
        )
        router.permissionMode = .autoAccept
        let bridge = MCPBridge()
        let config = MCPConfig(mcpServers: [
            "web-search": MCPServerConfig(
                command: "/usr/bin/swift",
                args: [
                    "run",
                    "--quiet",
                    "--package-path",
                    Self.packagePath,
                    "web-search-plugin",
                ],
                transportKind: .stdio
            )
        ])

        try await bridge.start(config: config, toolRouter: router)

        let loadedSchemas = await runtime.bus.registeredSettingsSchemas()
        XCTAssertTrue(loadedSchemas.contains { $0.namespace == "plugin.web_search" })
        XCTAssertRoute(router, "web_provider_status", capability: "provider_status")
        XCTAssertRoute(router, "web_search", capability: "search")
        XCTAssertRoute(router, "web_extract_page", capability: "extract_page")
        XCTAssertRoute(router, "web_search_and_extract", capability: "search_and_extract")
        XCTAssertRoute(router, "web_clear_cache", capability: "clear_cache")

        let status = await dispatch(router, name: "web_provider_status", arguments: "{}")
        XCTAssertFalse(status.isError)
        XCTAssertTrue(status?.content.contains("duckduckgo_lite") == true, status?.content ?? "")

        let disabledSettings = """
        {
          "query": "merlin",
          "settings": {
            "duckduckgo_lite_enabled": false,
            "wikipedia_enabled": false,
            "github_search_enabled": false,
            "stack_exchange_enabled": false,
            "hacker_news_enabled": false
          }
        }
        """
        let search = await dispatch(router, name: "web_search", arguments: disabledSettings)
        XCTAssertFalse(search.isError)
        XCTAssertTrue(search?.content.contains(#""query":"merlin""#) == true, search?.content ?? "")

        let searchAndExtract = await dispatch(router, name: "web_search_and_extract", arguments: disabledSettings)
        XCTAssertFalse(searchAndExtract.isError)
        XCTAssertTrue(searchAndExtract?.content.contains(#""extractions":[]"#) == true, searchAndExtract?.content ?? "")

        let extraction = await dispatch(router, name: "web_extract_page", arguments: #"{"url":"not-a-url"}"#)
        XCTAssertFalse(extraction.isError)
        XCTAssertTrue(extraction?.content.contains(#""state":"blocked""#) == true, extraction?.content ?? "")

        let clearCache = await dispatch(router, name: "web_clear_cache", arguments: "{}")
        XCTAssertFalse(clearCache.isError)
        XCTAssertTrue(clearCache?.content.contains("cache cleared") == true, clearCache?.content ?? "")

        await bridge.stop(toolRouter: router)

        let unloadedSchemas = await runtime.bus.registeredSettingsSchemas()
        XCTAssertFalse(unloadedSchemas.contains { $0.namespace == "plugin.web_search" })
        XCTAssertNil(router.route(for: "web_provider_status"))
        XCTAssertNil(router.route(for: "web_search"))
        XCTAssertNil(router.route(for: "web_extract_page"))
        XCTAssertNil(router.route(for: "web_search_and_extract"))
        XCTAssertNil(router.route(for: "web_clear_cache"))
    }

    private static var packagePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("plugins/web-search")
            .path
    }

    private func XCTAssertRoute(
        _ router: ToolRouter,
        _ toolName: String,
        capability: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            router.route(for: toolName)?.address,
            WorkspaceMessageAddress(namespace: "plugin.web_search", capability: capability),
            file: file,
            line: line
        )
    }

    private func dispatch(_ router: ToolRouter, name: String, arguments: String) async -> ToolResult? {
        await router.dispatch([ToolCall(
            id: UUID().uuidString,
            type: "function",
            function: FunctionCall(name: name, arguments: arguments)
        )]).first
    }
}

private extension Optional where Wrapped == ToolResult {
    var isError: Bool {
        self?.isError ?? true
    }
}
