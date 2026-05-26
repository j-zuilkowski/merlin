import XCTest
@testable import Merlin

@MainActor
final class RuntimePluginDynamicLoadingTests: XCTestCase {
    func testTierOnePluginDispatchesThroughDynamicHandler() async throws {
        let root = try temporaryDirectory("dynamic-plugin-root")
        let pluginDirectory = root.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)

        let libraryURL = try buildFixtureDynamicLibrary(in: pluginDirectory)
        let manifest = """
        {
          "id": "fixture",
          "display_name": "Fixture",
          "version": "1.0.0",
          "trust_tier": "tier1",
          "enabled": true,
          "domain_ids": ["fixture"],
          "dynamic_library_path": "\(libraryURL.path)",
          "bootstrap_symbol": "merlin_plugin_bootstrap_json",
          "handler_symbol": "merlin_plugin_handle_json",
          "capabilities": [
            {
              "id": "plugin.fixture.echo",
              "display_name": "Echo",
              "kind": "tool",
              "address": { "namespace": "plugin.fixture", "capability": "echo" },
              "required_permission_scope": "readOnly"
            }
          ]
        }
        """
        try manifest.write(to: pluginDirectory.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        let runtime = try testRuntime()
        try await RuntimePluginLoader(pluginRoots: [root]).load(into: runtime)

        let response = await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.fixture", capability: "echo"),
            origin: .parentSession(workspaceID: runtime.workspaceID, sessionID: nil, activeDomainIDs: []),
            payload: .jsonString(#"{"message":"hello"}"#),
            cancellationGroup: nil
        ))

        XCTAssertEqual(response.status, .ok)
        XCTAssertTrue(response.payload?.stringValue().contains("dynamic-ok") ?? false)
    }

    private func buildFixtureDynamicLibrary(in directory: URL) throws -> URL {
        let sourceURL = directory.appendingPathComponent("fixture.c")
        let libraryURL = directory.appendingPathComponent("libfixture.dylib")
        let source = """
        const char *merlin_plugin_bootstrap_json(void) {
            return "{\\"status\\":\\"loaded\\"}";
        }
        const char *merlin_plugin_handle_json(const char *request_json) {
            return "{\\"status\\":\\"dynamic-ok\\"}";
        }
        """
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = ["-dynamiclib", sourceURL.path, "-o", libraryURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return libraryURL
    }
}

