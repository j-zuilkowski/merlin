import XCTest
import Darwin
@testable import Merlin

@MainActor
final class WorkspaceRuntimePluginLaunchTests: XCTestCase {
    func testProjectDeclaresElectronicsPluginCopyOutput() throws {
        let project = try repoText("project.yml")
        XCTAssertTrue(project.contains("Copy first-party electronics plugin dylib"))
        XCTAssertTrue(project.contains("outputFiles:"))
        XCTAssertTrue(project.contains("$(SRCROOT)/plugins/electronics/libMerlinElectronicsPlugin.dylib"))
        XCTAssertTrue(project.contains("codesign --force --sign -"))
    }

    func testCopiedElectronicsPluginDylibCanBeDlopened() throws {
        let libraryURL = repoURL("plugins/electronics/libMerlinElectronicsPlugin.dylib")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: libraryURL.path),
            "Expected the MerlinElectronicsPlugin build step to copy \(libraryURL.path)"
        )

        let handle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        let error = handle == nil ? dlerror().map { String(cString: $0) } ?? "unknown dlopen error" : ""
        XCTAssertNotNil(handle, error)
        if let handle {
            dlclose(handle)
        }
    }

    func testWorkspaceRuntimeLoadsEnabledElectronicsPluginFromRoot() async throws {
        let root = temporaryDirectory("runtime-plugin-root")
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
