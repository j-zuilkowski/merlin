import XCTest
@testable import Merlin

@MainActor
final class RuntimePluginLoaderTests: XCTestCase {
    func testDiscoversFirstPartyPluginMetadata() throws {
        let root = try makePluginRoot()
        try writePlugin(
            root: root,
            id: "electronics",
            displayName: "Electronics",
            tier: "tier1",
            enabled: true
        )

        let loader = RuntimePluginLoader(pluginRoots: [root])
        let plugins = try loader.discover()

        XCTAssertEqual(plugins.map(\.id), ["electronics"])
        XCTAssertEqual(plugins.first?.trustTier, .tier1)
        XCTAssertEqual(plugins.first?.capabilities.first?.address.namespace, "plugin.electronics")
    }

    func testEnabledTierOnePluginWithoutEntrypointDoesNotRegisterPlaceholderRoutes() async throws {
        let root = try makePluginRoot()
        try writePlugin(root: root, id: "demo", displayName: "Demo", tier: "tier1", enabled: true)
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-plugin-tests-\(UUID().uuidString)")
        )

        let loader = RuntimePluginLoader(pluginRoots: [root])
        try await loader.load(into: runtime)

        let hasRoute = await runtime.bus.hasRoute(WorkspaceMessageAddress(namespace: "plugin.demo", capability: "health"))
        XCTAssertFalse(hasRoute)
        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.demo"))
        XCTAssertTrue(events.contains { $0.kind == .healthChanged })
    }

    func testDisabledPluginDoesNotRegisterRoutesAndTierTwoIsTransportOnly() async throws {
        let root = try makePluginRoot()
        try writePlugin(root: root, id: "disabled", displayName: "Disabled", tier: "tier1", enabled: false)
        try writePlugin(root: root, id: "remote", displayName: "Remote", tier: "tier2", enabled: true)
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-plugin-tests-\(UUID().uuidString)")
        )

        let loader = RuntimePluginLoader(pluginRoots: [root])
        try await loader.load(into: runtime)

        let disabledRoute = await runtime.bus.hasRoute(WorkspaceMessageAddress(namespace: "plugin.disabled", capability: "health"))
        let remoteRoute = await runtime.bus.hasRoute(WorkspaceMessageAddress(namespace: "plugin.remote", capability: "health"))
        XCTAssertFalse(disabledRoute)
        XCTAssertFalse(remoteRoute)
        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.remote"))
        XCTAssertTrue(events.contains { $0.kind == .healthChanged })
    }

    private func makePluginRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-plugin-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writePlugin(root: URL, id: String, displayName: String, tier: String, enabled: Bool) throws {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {
          "id": "\(id)",
          "display_name": "\(displayName)",
          "version": "1.0.0",
          "trust_tier": "\(tier)",
          "enabled": \(enabled),
          "domain_ids": ["\(id)"],
          "capabilities": [
            {
              "id": "plugin.\(id).health",
              "display_name": "Health",
              "kind": "tool",
              "address": { "namespace": "plugin.\(id)", "capability": "health" },
              "required_permission_scope": "readOnly"
            }
          ]
        }
        """
        try json.write(to: directory.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
    }
}
