import XCTest
@testable import Merlin

@MainActor
final class WorkspaceRuntimePluginLaunchTests: XCTestCase {
    func testWorkspaceRuntimeLoadsEnabledElectronicsPluginFromRoot() async throws {
        let root = try temporaryDirectory("runtime-plugin-root")
        let pluginDirectory = root.appendingPathComponent("electronics", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repoURL("plugins/electronics/plugin.json"),
            to: pluginDirectory.appendingPathComponent("plugin.json")
        )

        let runtime = try testRuntime()
        try await runtime.loadPlugins(pluginRoots: [root])

        let route = WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_route_pass")
        let hasRoute = await runtime.bus.hasRoute(route)
        XCTAssertTrue(hasRoute)
        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
        XCTAssertTrue(events.contains { $0.kind == .healthChanged })
    }
}
