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

    func testCleanBackendAmpValidationSliceCompilesAndRunsPassingERCSPICEDRC() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)

        let designIntent = repoURL("plugins/electronics/fixtures/amp_low_voltage_audio/design_intent.json")
        let compileOutput = temporaryDirectory("amp-backend-validation-slice")
        let compile = await sendElectronics(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_intent_path":"\#(designIntent.path)","output_directory":"\#(compileOutput.path)"}"#
        )
        XCTAssertEqual(compile.status, .ok)
        let compileResult = try XCTUnwrap(compile.payload?.decodeJSON(KiCadToolResult.self))
        let projectPath = try XCTUnwrap(compileResult.artifacts.first { $0.kind == ElectronicsArtifactKind.kicadProject.rawValue }?.path)
        let boardPath = try XCTUnwrap(compileResult.artifacts.first { $0.kind == ElectronicsArtifactKind.board.rawValue }?.path)
        let boardText = try String(contentsOfFile: boardPath, encoding: .utf8)
        XCTAssertTrue(boardText.contains(#"layer "Edge.Cuts""#), boardText)

        let kicad = try writeFakeKiCadCLI(reportJSON: #"{"violations":[]}"#)
        let erc = await sendElectronics(
            runtime,
            capability: "kicad_run_erc",
            payload: #"{"project_path":"\#(projectPath)","kicad_cli_path":"\#(kicad.executable.path)"}"#
        )
        XCTAssertEqual(erc.status, .ok)
        let ercResult = try XCTUnwrap(erc.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(ercResult.artifacts.contains { $0.kind == "erc_report" && FileManager.default.fileExists(atPath: $0.path) })

        let drc = await sendElectronics(
            runtime,
            capability: "kicad_run_drc",
            payload: #"{"project_path":"\#(projectPath)","kicad_cli_path":"\#(kicad.executable.path)"}"#
        )
        XCTAssertEqual(drc.status, .ok)
        let drcResult = try XCTUnwrap(drc.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(drcResult.artifacts.contains { $0.kind == "drc_report" && FileManager.default.fileExists(atPath: $0.path) })

        let deck = try writeFixtureFile(name: "amp-pass.cir", text: """
        * passing amp slice
        V1 in 0 DC 1
        R1 in 0 1k
        .op
        .end
        """)
        let ngspice = try writeFakeNgspice(exitCode: 0, logText: "output_power_w = 25.0\\nthd_percent = 0.7\\n")
        let spice = await sendElectronics(
            runtime,
            capability: "kicad_run_spice",
            payload: #"{"project_path":"\#(projectPath)","scenario_path":"\#(deck.path)","ngspice_path":"\#(ngspice.path)"}"#
        )
        XCTAssertEqual(spice.status, .ok)
        let spiceResult = try XCTUnwrap(spice.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(spiceResult.artifacts.contains { $0.kind == "spice_measurements" && FileManager.default.fileExists(atPath: $0.path) })

        let log = try String(contentsOf: kicad.log, encoding: .utf8)
        XCTAssertTrue(log.contains("sch erc"))
        XCTAssertTrue(log.contains("pcb drc"))
    }

    func testSPICEScenarioGenerationProducesRunnableDeckArtifact() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)
        let project = try writeFixtureFile(name: "scenario-source.kicad_pro", text: #"{"meta":{"version":1}}"#)

        let scenario = await sendElectronics(
            runtime,
            capability: "kicad_generate_spice_scenario",
            payload: #"{"project_path":"\#(project.path)"}"#
        )

        XCTAssertEqual(scenario.status, .ok)
        let scenarioResult = try XCTUnwrap(scenario.payload?.decodeJSON(KiCadToolResult.self))
        let scenarioPath = try XCTUnwrap(scenarioResult.artifacts.first { $0.kind == "simulation_scenario" }?.path)
        XCTAssertEqual(scenarioResult.handoff?.simulationScenarioPath, scenarioPath)
        XCTAssertTrue(scenarioResult.nextActions.contains("kicad_run_spice"))
        let deck = try String(contentsOfFile: scenarioPath, encoding: .utf8)
        XCTAssertTrue(deck.contains(".tran"), deck)
        XCTAssertTrue(deck.contains(".end"), deck)

        let ngspice = try writeFakeNgspice(exitCode: 0, logText: "peak_output_v = 1.0\\nrms_output_v = 0.707\\n")
        let spice = await sendElectronics(
            runtime,
            capability: "kicad_run_spice",
            payload: #"{"project_path":"\#(project.path)","scenario_path":"\#(scenarioPath)","ngspice_path":"\#(ngspice.path)"}"#
        )
        XCTAssertEqual(spice.status, .ok)
        let spiceResult = try XCTUnwrap(spice.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(spiceResult.artifacts.contains { $0.kind == "spice_measurements" && FileManager.default.fileExists(atPath: $0.path) })
    }

    func testCompiledBoardOutlinePassesRealKiCadDRCWhenAvailable() async throws {
        let kicadCLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
        guard FileManager.default.isExecutableFile(atPath: kicadCLI) else {
            throw XCTSkip("KiCad CLI is not installed at \(kicadCLI)")
        }
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)
        let designIntent = try writeFixtureFile(name: "intent.json", text: #"{"design_id":"fixture","title":"Fixture"}"#)
        let compileOutput = temporaryDirectory("real-drc-board-outline")

        let compile = await sendElectronics(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_intent_path":"\#(designIntent.path)","output_directory":"\#(compileOutput.path)"}"#
        )

        XCTAssertEqual(compile.status, .ok)
        let compileResult = try XCTUnwrap(compile.payload?.decodeJSON(KiCadToolResult.self))
        let boardPath = try XCTUnwrap(compileResult.artifacts.first { $0.kind == ElectronicsArtifactKind.board.rawValue }?.path)
        let report = compileOutput.appendingPathComponent("drc.json")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: kicadCLI)
        process.arguments = ["pcb", "drc", "--format", "json", "--output", report.path, boardPath]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let reportText = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(reportText.contains(#""violations": []"#), reportText)
    }

    func testKiCadERCGateBlocksOnParsedBlockingDiagnostics() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)
        let project = try writeKiCadProjectFixture(name: "erc-block")
        let tool = try writeFakeKiCadCLI(reportJSON: #"{"violations":[{"id":"erc-1","code":"power_pin_not_driven","severity":"error","message":"Power input not driven","refs":["U1.1"]}]}"#)

        let response = await sendElectronics(
            runtime,
            capability: "kicad_run_erc",
            payload: #"{"project_path":"\#(project.path)","kicad_cli_path":"\#(tool.executable.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.violations.map(\.gate), ["erc"])
        XCTAssertEqual(result.violations.map(\.code), ["power_pin_not_driven"])
        XCTAssertTrue(result.warnings.contains { $0.code == "power_pin_not_driven" })
        XCTAssertTrue(result.nextActions.contains("repair_erc_from_diagnostics"))
        let ercPath = try XCTUnwrap(result.artifacts.first { $0.kind == "erc_report" }?.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ercPath))
        XCTAssertEqual(result.handoff?.ercReportPath, ercPath)
    }

    func testKiCadDRCGateBlocksOnParsedBlockingDiagnostics() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)
        let project = try writeKiCadProjectFixture(name: "drc-block")
        let tool = try writeFakeKiCadCLI(reportJSON: #"{"violations":[{"id":"drc-1","code":"clearance","severity":"error","message":"Track clearance violation","refs":["R1","C1"]}]}"#)

        let response = await sendElectronics(
            runtime,
            capability: "kicad_run_drc",
            payload: #"{"project_path":"\#(project.path)","kicad_cli_path":"\#(tool.executable.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.violations.map(\.gate), ["drc"])
        XCTAssertEqual(result.violations.map(\.code), ["clearance"])
        XCTAssertTrue(result.warnings.contains { $0.code == "clearance" })
        XCTAssertTrue(result.nextActions.contains("repair_drc_from_diagnostics"))
        let drcPath = try XCTUnwrap(result.artifacts.first { $0.kind == "drc_report" }?.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: drcPath))
        XCTAssertEqual(result.handoff?.drcReportPath, drcPath)
    }

    func testSPICEGateBlocksOnNgspiceErrorsAndPreservesRepairDiagnostics() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)
        let project = try writeKiCadProjectFixture(name: "spice-block")
        let scenario = try writeFixtureFile(name: "amp.cir", text: """
        * failing fixture
        V1 in 0 DC 1
        R1 in 0 1k
        .op
        .end
        """)
        let tool = try writeFakeNgspice(exitCode: 1, logText: "Error: singular matrix\\n")

        let response = await sendElectronics(
            runtime,
            capability: "kicad_run_spice",
            payload: #"{"project_path":"\#(project.path)","scenario_path":"\#(scenario.path)","ngspice_path":"\#(tool.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(result.status, .blockedSimulation)
        XCTAssertTrue(result.warnings.contains { $0.code == "SPICE_EXECUTION_FAILED" && $0.message.contains("singular matrix") })
        XCTAssertTrue(result.nextActions.contains("repair_spice_from_diagnostics"))
        XCTAssertTrue(result.artifacts.contains { $0.kind == "spice_measurements" && FileManager.default.fileExists(atPath: $0.path) })
    }

    func testSPICEGateBlocksOutOfEnvelopeMeasurementsAndKeepsLog() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin(tooling: .available, routeBackend: RecordingElectronicsRouteBackend(result: KiCadToolResult(status: .complete))).register(into: runtime)
        let project = try writeKiCadProjectFixture(name: "spice-envelope-block")
        let scenario = try writeFixtureFile(name: "amp.cir", text: """
        * passing simulator run with failing measurement envelope
        V1 out 0 SIN(0 1 1000)
        RLOAD out 0 8
        .tran 10u 10m
        .meas tran output_power_w PARAM='1.5'
        .end
        """)
        let tool = try writeFakeNgspice(exitCode: 0, logText: "output_power_w = 1.5\\n")

        let response = await sendElectronics(
            runtime,
            capability: "kicad_run_spice",
            payload: #"{"project_path":"\#(project.path)","scenario_path":"\#(scenario.path)","ngspice_path":"\#(tool.path)","measurement_envelopes":[{"name":"output_power_w","min":24.0,"max":28.0}]}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertEqual(result.status, .blockedSimulation)
        XCTAssertTrue(result.warnings.contains { $0.code == "SPICE_MEASUREMENT_OUT_OF_ENVELOPE" && $0.message.contains("output_power_w") })
        XCTAssertTrue(result.nextActions.contains("repair_spice_from_diagnostics"))
        XCTAssertTrue(result.artifacts.contains { $0.kind == "spice_measurements" && FileManager.default.fileExists(atPath: $0.path) })
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

    private func writeKiCadProjectFixture(name: String) throws -> URL {
        let directory = temporaryDirectory(name)
        let project = directory.appendingPathComponent("\(name).kicad_pro")
        let schematic = directory.appendingPathComponent("\(name).kicad_sch")
        let board = directory.appendingPathComponent("\(name).kicad_pcb")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{}".write(to: project, atomically: true, encoding: .utf8)
        try "(kicad_sch)".write(to: schematic, atomically: true, encoding: .utf8)
        try "(kicad_pcb)".write(to: board, atomically: true, encoding: .utf8)
        return project
    }

    private func writeFakeKiCadCLI() throws -> (executable: URL, log: URL) {
        try writeFakeKiCadCLI(reportJSON: #"{"status":"pass","violations":[]}"#)
    }

    private func writeFakeKiCadCLI(reportJSON: String) throws -> (executable: URL, log: URL) {
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
            cat > "$1" <<'JSON'
        \(reportJSON)
        JSON
          fi
          shift
        done
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (executable, log)
    }

    private func writeFakeNgspice(exitCode: Int, logText: String) throws -> URL {
        let directory = temporaryDirectory("fake-ngspice")
        let executable = directory.appendingPathComponent("ngspice")
        let script = """
        #!/bin/sh
        out=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-o" ]; then
            shift
            out="$1"
          fi
          shift
        done
        mkdir -p "$(dirname "$out")"
        printf '%s' "\(logText)" > "$out"
        exit \(exitCode)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
