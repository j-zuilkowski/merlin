import Foundation
import XCTest
@testable import Merlin

/// W5 - M1 capability harness. Drives the S1-S6 capability scenarios end to end. Each
/// test launches and tears down whatever external service it needs - nothing is started
/// by hand. Judgement rubric items (visuals, debugging soundness) are scored by a human
/// against the logged `EvalRun`.
final class CapabilityScenarioTests: XCTestCase {

    // MARK: - S1 - Swift GUI debug cycle

    @MainActor
    func testS1SwiftGUIDebugCycle() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("swift-gui-buggy"),
                          "S1 fixture missing - build fixtures/S1-taskboard-fixture.md")
        let fixture = EvalPaths.fixture("swift-gui-buggy")

        let run = try await EvalHarness.runScenario(
            fixturePath: fixture, prompt: EvalPrompts.s1, timeout: 1800)
        XCTAssertTrue(run.errors.isEmpty, "S1 engine errors: \(run.errors)")

        _ = EvalShell.run("/usr/bin/xcodegen", ["generate"], cwd: fixture)
        let testOut = EvalShell.run("/usr/bin/xcodebuild",
            ["-scheme", "TaskBoard", "test", "-destination", "platform=macOS",
             "CODE_SIGN_IDENTITY=", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO"],
            cwd: fixture)
        EvalLog.write(scenario: "S1", summary: "tools \(run.toolCalls.count) "
            + "errors \(run.errors.count)\n\(testOut.suffix(600))\n\(run.assistantText)")
        XCTAssertTrue(testOut.contains("TEST SUCCEEDED"),
                      "S1: TaskBoardTests must pass after Merlin's fixes")
    }

    // MARK: - S2 - Rust debug cycle

    @MainActor
    func testS2RustDebugCycle() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("rust-buggy"),
                          "S2 fixture missing - build fixtures/S2-ledger-fixture.md")
        let fixture = EvalPaths.fixture("rust-buggy")

        let run = try await EvalHarness.runScenario(
            fixturePath: fixture, prompt: EvalPrompts.s2, timeout: 1800)
        XCTAssertTrue(run.errors.isEmpty, "S2 engine errors: \(run.errors)")

        // Run via `zsh -c` (sources the user's env) — `/usr/bin/env` execs with the
        // test process's minimal PATH, which lacks `~/.cargo/bin`, so `cargo` is unfound.
        let testOut = EvalShell.run("/bin/zsh", ["-c", "cargo test"], cwd: fixture)
        EvalLog.write(scenario: "S2", summary: "tools \(run.toolCalls.count)\n"
            + "\(testOut.suffix(600))\n\(run.assistantText)")
        XCTAssertTrue(testOut.contains("test result: ok"),
                      "S2: cargo test must be green after Merlin's fixes")
    }

    // MARK: - S4 - xcalibre RAG (harness launches xcalibre-server)

    @MainActor
    func testS4RAGGrounding() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("rag-corpus"),
                          "S4 fixture missing - build fixtures/S4-rag-corpus-fixture.md")

        // 1. Build the xcalibre-server backend binary.
        let serverDir = EvalPaths.sibling("xcalibre-server")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: serverDir),
                          "xcalibre-server repo not found beside merlin")
        _ = EvalShell.run("/bin/zsh", ["-c", "cargo build -p backend"], cwd: serverDir)
        let binary = "\(serverDir)/target/debug/backend"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: binary),
                          "xcalibre-server backend did not build")

        // 2. Write a private config - temp DB + storage, and a watch-folder pointed at
        //    the corpus (the watch folder ingests EPUBs with no auth). The backend
        //    reads the file named by the `CONFIG_PATH` env var
        //    (xcalibre-server/backend/src/config.rs:598). Confirm the `[database]` /
        //    `[app]` key names against `xcalibre-server/config.example.toml`.
        let port = 8094
        let work = NSTemporaryDirectory() + "xcalibre-server-eval-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: work) }
        // The RAG pipeline needs an LLM for reranking. Use Merlin's configured
        // non-vision LM Studio provider - its real endpoint + model - not a guess.
        guard let lm = EvalLMStudio.textProvider() else {
            throw XCTSkip("no non-vision LM Studio provider configured - "
                          + "S4 reranking needs a text model")
        }
        // Key names must match xcalibre-server's config structs (config.rs):
        // [app] base_url + storage_path are both validated-required; [database] is a
        // single `url` field that must be a sqlite:// URL — not a `path`.
        let configPath = "\(work)/config.toml"
        try """
        [app]
        base_url = "http://127.0.0.1:\(port)"
        storage_path = "\(work)/storage"
        [database]
        url = "sqlite://\(work)/library.db"
        [watch_folder]
        enabled = true
        path = "\(EvalPaths.fixture("rag-corpus"))"
        interval_seconds = 2
        [llm]
        enabled = true
        allow_private_endpoints = true
        [llm.librarian]
        endpoint = "\(lm.baseURL)"
        model = "\(lm.model)"
        """.write(toFile: configPath, atomically: true, encoding: .utf8)

        let server = EvalService(label: "xcalibre-server")
        try server.launch(executable: binary, cwd: serverDir,
                          env: ["CONFIG_PATH": configPath,
                                "APP_BIND_ADDR": "127.0.0.1:\(port)"])
        defer { server.terminate() }
        let ready = await server.waitUntilReady(
            url: "http://127.0.0.1:\(port)/api/docs/openapi.json", timeout: 120)
        XCTAssertTrue(ready, "xcalibre-server did not become ready")
        // Give the watch-folder scan time to ingest the 2 EPUBs.
        try await Task.sleep(nanoseconds: 8_000_000_000)

        // 3. Point Merlin's xcalibre-server client at the instance and run the scenario.
        setenv("XCALIBRE_BASE_URL", "http://127.0.0.1:\(port)", 1)
        defer { unsetenv("XCALIBRE_BASE_URL") }
        let run = try await EvalHarness.runScenario(
            fixturePath: EvalPaths.fixture("rag-corpus"),
            prompt: EvalPrompts.s4, timeout: 900)

        EvalLog.write(scenario: "S4", summary: "errors \(run.errors.count)\n\(run.assistantText)")
        let answer = run.assistantText.lowercased()
        XCTAssertTrue(answer.contains("47") && answer.contains("tangerine"),
                      "S4: grounded facts (47 kPa, TANGERINE-7) must be retrieved")
        XCTAssertFalse(answer.contains("rotational speed") && answer.contains("rpm"),
                       "S4: Q4 is absent from the corpus - Merlin must not hallucinate it")
    }

    // MARK: - S5 - LoRA pipeline (harness seeds pairs + auto-trains)

    @MainActor
    func testS5LoRAPipeline() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("lora-dpo"),
                          "S5 fixture missing - build fixtures/S5-lora-dpo-fixture.md")
        let mlx = EvalShell.run("/bin/zsh", ["-c", "python3 -c 'import mlx_lm'"], cwd: "/tmp")
        try XCTSkipUnless(!mlx.contains("Error") && !mlx.contains("Traceback"),
                          "mlx_lm not importable - S5 needs the LoRA training environment")

        // 1. Build OutcomeRecords from the fixture's DPO pairs (prompt + chosen).
        //    LoRATrainer reads only .prompt / .response; the other fields are valid
        //    placeholders (OutcomeRecord - ModelPerformanceTracker.swift).
        struct DPOPair: Decodable { let prompt: String; let chosen: String }
        let pendingDir = EvalPaths.fixture("lora-dpo") + "/pending"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: pendingDir)) ?? []
        var records: [OutcomeRecord] = []
        for f in files where f.hasSuffix(".json") {
            let data = try Data(contentsOf: URL(fileURLWithPath: "\(pendingDir)/\(f)"))
            let pair = try JSONDecoder().decode(DPOPair.self, from: data)
            records.append(OutcomeRecord(
                modelID: "eval-s5",
                taskType: DomainTaskType(domainID: "eval", name: "lora", displayName: "LoRA"),
                score: 1.0, addendumHash: "", timestamp: Date(),
                prompt: pair.prompt, response: pair.chosen,
                legacyTrainingRecord: false, finishReason: nil))
        }
        try XCTSkipUnless(records.count >= 20, "S5 needs the seeded DPO pairs")

        // 2. Run the real training pipeline - LoRATrainer drives `python -m mlx_lm.lora`.
        //    The base model is Merlin's configured non-vision LM Studio model - the
        //    text model, picked by capability, not the first one listed.
        guard let lm = EvalLMStudio.textProvider() else {
            throw XCTSkip("no non-vision LM Studio provider configured - "
                          + "S5 needs a text base model")
        }
        let adapterDir = NSTemporaryDirectory() + "merlin-lora-adapter-\(UUID())"
        let result = await LoRATrainer().train(
            records: records,
            baseModel: lm.model,
            adapterOutputPath: adapterDir,
            iterations: 20)

        // 3. Assert the pipeline completed and produced an adapter artifact.
        EvalLog.write(scenario: "S5", summary: "samples \(result.sampleCount) "
            + "success \(result.success) error \(result.errorMessage ?? "-")")
        XCTAssertTrue(result.success,
                      "S5: the LoRA pipeline must complete - \(result.errorMessage ?? "")")
        let adapterFiles = (try? FileManager.default.contentsOfDirectory(atPath: adapterDir)) ?? []
        XCTAssertFalse(adapterFiles.isEmpty, "S5: training must produce an adapter artifact")
    }

    // MARK: - S6 - electronics (harness writes the MCP config; Merlin spawns the server)

    @MainActor
    func testS6Electronics() async throws {
        try skipUnlessLiveEnvironment()
        // The merlin-kicad-mcp server is launched BY Merlin from the project's
        // `.mcp.json` - the harness only writes that config; no service to manage here.
        let fixture = EvalPaths.fixture("electronics")
        try? FileManager.default.createDirectory(
            atPath: fixture, withIntermediateDirectories: true)

        // Skip on the launchable `run` executable, not the plugin directory — the dir
        // exists as phase docs long before the MCP server is actually built.
        let mcpServerPath = "\(EvalPaths.sibling("merlin"))/plugins/merlin-kicad-mcp"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "\(mcpServerPath)/run"),
                          "merlin-kicad-mcp server not built — no run executable")
        let mcpJSON = """
        { "mcpServers": { "kicad": { "command": "\(mcpServerPath)/run", "transport": "stdio" } } }
        """
        try mcpJSON.write(toFile: "\(fixture)/.mcp.json", atomically: true, encoding: .utf8)
        // (Confirm the merlin-kicad-mcp launch command from its README.)

        let run = try await EvalHarness.runScenario(
            fixturePath: fixture, prompt: EvalPrompts.s6, timeout: 1800)
        EvalLog.write(scenario: "S6", summary: "tools \(run.toolCalls.count) "
            + "errors \(run.errors.count)\n\(run.assistantText)")
        XCTAssertTrue(run.toolCalls.contains { $0.name.hasPrefix("kicad_") }
                      || run.toolCalls.contains { $0.name.hasPrefix("mcp:") },
                      "S6: Merlin must call the KiCad MCP tools")
    }

    // MARK: - S6 Part B - schematic OCR (needs the vision model)

    @MainActor
    func testS6SchematicOCR() async throws {
        try skipUnlessLiveEnvironment()
        let fixture = EvalPaths.fixture("electronics")
        let image = "\(fixture)/schematic-image/rc-filter.png"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: image),
                          "S6 OCR fixture missing - build fixtures/S6-electronics-fixture.md")

        // Schematic OCR is a vision task - route Merlin's vision slot at the
        // vision-capable LM Studio model (picked by capability, not the first listed).
        guard let vision = EvalLMStudio.visionProvider() else {
            throw XCTSkip("no vision-capable LM Studio provider configured - "
                          + "schematic OCR needs a vision model")
        }
        let priorVision = AppSettings.shared.slotAssignments[.vision]
        AppSettings.shared.slotAssignments[.vision] = vision.id
        defer { AppSettings.shared.slotAssignments[.vision] = priorVision }

        // The KiCad MCP server (Merlin spawns it) lets Merlin write the extracted
        // schematic; same config as Part A.
        let mcpServerPath = "\(EvalPaths.sibling("merlin"))/plugins/merlin-kicad-mcp"
        if FileManager.default.fileExists(atPath: "\(mcpServerPath)/run") {
            let mcpJSON = """
            { "mcpServers": { "kicad": { "command": "\(mcpServerPath)/run", "transport": "stdio" } } }
            """
            try mcpJSON.write(toFile: "\(fixture)/.mcp.json", atomically: true, encoding: .utf8)
        }

        let run = try await EvalHarness.runScenario(
            fixturePath: fixture,
            prompt: EvalPrompts.s6OCR(imagePath: image),
            timeout: 900)

        // Ground truth (fixtures/S6 ground-truth.json): R1 10k, C1 100nF.
        let report = run.assistantText
        EvalLog.write(scenario: "S6-OCR", summary: "vision-model \(vision.model) "
            + "tools \(run.toolCalls.count) errors \(run.errors.count)\n\(report)")
        XCTAssertTrue(report.contains("R1") && report.contains("C1"),
                      "S6 OCR: both components (R1, C1) must be recognised")
        XCTAssertTrue(report.contains("10k") || report.contains("10 k"),
                      "S6 OCR: R1's value (10k) must be read")
        XCTAssertTrue(report.contains("100n") || report.lowercased().contains("100 nf"),
                      "S6 OCR: C1's value (100nF) must be read")
    }
}
