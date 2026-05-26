import XCTest
@testable import Merlin

@MainActor
final class FullGreenRuntimeElectronicsTests: XCTestCase {
    func testRuntimeLoaderHasNoElectronicsIDShortcut() throws {
        let source = try repoText("Merlin/Plugins/RuntimePluginLoader.swift")
        XCTAssertFalse(source.contains(#"plugin.id == "electronics""#))
        XCTAssertFalse(source.contains(#"plugin.builtInFactory == "electronics""#))
    }

    func testProjectBuildsFirstPartyElectronicsDynamicLibrary() throws {
        let project = try repoText("project.yml")
        XCTAssertTrue(project.contains("MerlinElectronicsPlugin"))
        XCTAssertTrue(project.contains("plugins/electronics/Sources"))
        XCTAssertTrue(project.contains("libMerlinElectronicsPlugin.dylib"))
    }

    func testWorkspaceLoaderUsesDynamicElectronicsGate() async throws {
        let root = temporaryDirectory("dynamic-electronics-plugin-root")
        let pluginDirectory = root.appendingPathComponent("electronics", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repoURL("plugins/electronics/plugin.json"),
            to: pluginDirectory.appendingPathComponent("plugin.json")
        )

        let libraryURL = try buildElectronicsDynamicLibrary(in: pluginDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path))

        let runtime = try testRuntime()
        try await RuntimePluginLoader(pluginRoots: [root]).load(into: runtime)

        let route = WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_run_erc")
        let hasRoute = await runtime.bus.hasRoute(route)
        XCTAssertTrue(hasRoute)

        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
        XCTAssertTrue(events.contains { $0.kind == .healthChanged && ($0.payload?.stringValue().contains("loaded-dynamic") ?? false) })
    }

    func testKiCadRoutesBlockWithoutRequiredExecutableAndInputs() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)
        let project = try writeFixtureFile(name: "board.kicad_pro", text: "{}")

        let erc = await sendElectronics(runtime, capability: "kicad_run_erc", payload: #"{"project_path":"\#(project.path)","kicad_cli_path":"/not/a/kicad-cli"}"#)
        let ercResult = try XCTUnwrap(erc.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(erc.status, .blocked)
        XCTAssertNotEqual(ercResult.status, .complete)
        XCTAssertTrue(ercResult.warnings.contains { $0.code == "KICAD_CLI_REQUIRED" })

        let fabOutput = temporaryDirectory("fab-output")
        let fab = await sendElectronics(runtime, capability: "kicad_export_fab", payload: #"{"project_path":"\#(project.path)","kicad_cli_path":"/not/a/kicad-cli","output_directory":"\#(fabOutput.path)","fabricator_profile_id":"jlcpcb_2layer_default"}"#)
        let fabResult = try XCTUnwrap(fab.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(fab.status, .blocked)
        XCTAssertNotEqual(fabResult.status, .complete)
        XCTAssertTrue(fabResult.warnings.contains { $0.code == "KICAD_CLI_REQUIRED" })

        let compileOutput = temporaryDirectory("compile-output")
        let compile = await sendElectronics(runtime, capability: "kicad_compile_project", payload: #"{"design_id":"missing-intent","output_directory":"\#(compileOutput.path)"}"#)
        let compileResult = try XCTUnwrap(compile.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(compile.status, .blocked)
        XCTAssertNotEqual(compileResult.status, .complete)
        XCTAssertTrue(compileResult.warnings.contains { $0.code == "DESIGN_INTENT_REQUIRED" })
    }

    func testKiCadHandlersInvokeExecutableAndProduceEvidenceArtifacts() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)

        let designIntent = try writeFixtureFile(name: "intent.json", text: #"{"design_id":"fixture","title":"Fixture"}"#)
        let compileOutput = temporaryDirectory("compile-real")
        let compile = await sendElectronics(runtime, capability: "kicad_compile_project", payload: #"{"design_id":"fixture","design_intent_path":"\#(designIntent.path)","output_directory":"\#(compileOutput.path)"}"#)
        XCTAssertEqual(compile.status, .ok)
        let compileResult = try XCTUnwrap(compile.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(compileResult.status, .complete)
        let projectPath = try XCTUnwrap(compileResult.artifacts.first { $0.kind == ElectronicsArtifactKind.kicadProject.rawValue }?.path)

        let tool = try writeFakeKiCadCLI()
        let erc = await sendElectronics(runtime, capability: "kicad_run_erc", payload: #"{"project_path":"\#(projectPath)","kicad_cli_path":"\#(tool.executable.path)"}"#)
        XCTAssertEqual(erc.status, .ok)
        XCTAssertTrue((try? String(contentsOf: tool.log, encoding: .utf8))?.contains("sch erc") ?? false)
        let ercResult = try XCTUnwrap(erc.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(ercResult.artifacts.contains { $0.kind == "erc_report" && FileManager.default.fileExists(atPath: $0.path) })

        let fabOutput = temporaryDirectory("fab-real")
        let fab = await sendElectronics(runtime, capability: "kicad_export_fab", payload: #"{"project_path":"\#(projectPath)","kicad_cli_path":"\#(tool.executable.path)","output_directory":"\#(fabOutput.path)","fabricator_profile_id":"jlcpcb_2layer_default"}"#)
        XCTAssertEqual(fab.status, .ok)
        let log = (try? String(contentsOf: tool.log, encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("pcb export gerbers"))
        XCTAssertTrue(log.contains("pcb export drill"))
        let fabResult = try XCTUnwrap(fab.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(fabResult.status, .complete)
        XCTAssertTrue(fabResult.artifacts.contains { $0.kind == "gerbers" && FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(fabResult.artifacts.contains { $0.kind == "drills" && FileManager.default.fileExists(atPath: $0.path) })
    }

    private func buildElectronicsDynamicLibrary(in directory: URL) throws -> URL {
        let sourceURL = repoURL("plugins/electronics/Sources/ElectronicsPluginEntrypoint.c")
        let libraryURL = directory.appendingPathComponent("libMerlinElectronicsPlugin.dylib")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = ["-dynamiclib", sourceURL.path, "-o", libraryURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return libraryURL
    }

    private func writeFixtureFile(name: String, text: String) throws -> URL {
        let directory = temporaryDirectory("electronics-fixture")
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeFakeKiCadCLI() throws -> (executable: URL, log: URL) {
        let directory = temporaryDirectory("fake-kicad")
        let executable = directory.appendingPathComponent("kicad-cli")
        let log = directory.appendingPathComponent("calls.log")
        let script = """
        #!/bin/sh
        echo "$@" >> "\(log.path)"
        case "$*" in
          *"--version"*) echo "KiCad Version: 10.0.0"; exit 0 ;;
        esac
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output" ]; then
            shift
            mkdir -p "$(dirname "$1")"
            echo "{\\"status\\":\\"pass\\",\\"tool\\":\\"$0\\"}" > "$1"
          fi
          shift
        done
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (executable, log)
    }
}
