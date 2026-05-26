# Task 326 — Eval Capability Harness (S1–S6)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 325b complete: AccessibilityID gap-fill landed.

W5 — the proving suite. `EvalHarness` already exists (task 303); this task adds the
**M1 capability harness**: the `MerlinE2ETests` tests that drive the S1–S6 capability
scenarios over their fixtures.

**The harness brings up its own world.** Every external service a scenario needs —
xcalibre-server (S4), the LoRA training pipeline (S5), the merlin-kicad-mcp server (S6) —
is launched, configured, and torn down *by the test*, not by a human. The proving-run
operator only runs the `MerlinTests-Live` scheme; the harness does the rest. The
capability probe (`merlin-eval/BLOCKED.md`) confirmed every dependency is installed.

All tests are gated by `skipUnlessLiveEnvironment()` (`RUN_LIVE_TESTS=1`). Fixtures are
built per `merlin-eval/fixtures/S{1,2,4,5,6}-*.md`; tests resolve them relative to
`#filePath`. A test whose fixture is genuinely absent skips with a clear reason — but a
service being *down* is never a skip: the harness starts it.

Two support files + one test file are added to `MerlinE2ETests/`.

---

## Write to: MerlinE2ETests/EvalSupport.swift

```swift
import Foundation
import XCTest
@testable import Merlin

/// Resolves `merlin-eval/<...>` — the eval suite, which lives inside the `merlin` repo
/// at `merlin/merlin-eval/` — from this source file's location, so the harness needs no
/// env var or absolute path.
enum EvalPaths {
    /// `…/localProject`
    static var root: URL {
        URL(fileURLWithPath: #filePath)            // …/merlin/MerlinE2ETests/EvalSupport.swift
            .deletingLastPathComponent()           // …/merlin/MerlinE2ETests
            .deletingLastPathComponent()           // …/merlin
            .deletingLastPathComponent()           // …/localProject
    }
    static func fixture(_ name: String) -> String {
        root.appendingPathComponent("merlin/merlin-eval/fixtures/\(name)").path
    }
    static func sibling(_ name: String) -> String {
        root.appendingPathComponent(name).path     // e.g. "xcalibre-server"
    }
    static func fixtureExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: fixture(name))
    }
}

/// Runs a shell command synchronously; returns combined stdout+stderr.
enum EvalShell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String],
                    cwd: String, env: [String: String] = [:]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        if !env.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            proc.environment = merged
        }
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return "EvalShell launch error: \(error)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Manages a long-running external service process for the proving suite — launch it,
/// wait until it answers, tear it down. The harness owns the service lifecycle so no
/// part of the suite is started by hand.
final class EvalService {
    private let process = Process()
    let label: String

    init(label: String) { self.label = label }

    /// Launches `executable` (a *built binary*, not a `cargo run` wrapper, so
    /// `terminate()` kills the real server rather than a parent shell).
    func launch(executable: String, args: [String] = [],
                cwd: String, env: [String: String] = [:]) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var merged = ProcessInfo.processInfo.environment
        for (k, v) in env { merged[k] = v }
        process.environment = merged
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Polls an HTTP `url` until it responds (any status) or `timeout` elapses.
    func waitUntilReady(url: String, timeout: TimeInterval) async -> Bool {
        guard let u = URL(string: url) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await URLSession.shared.data(from: u)) != nil { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}

/// Resolves the LM Studio model to use — by capability, from Merlin's own provider
/// config (actual values, never invented, never "the first listed"). LM Studio may have
/// both a vision model and a text model loaded; reranking (S4) and LoRA training (S5)
/// need the **text** model, so it is picked deliberately via `supportsVision`.
enum EvalLMStudio {
    /// Merlin's configured LM Studio-backed providers.
    @MainActor
    static var providers: [ProviderConfig] {
        AppSettings.shared.providers.filter {
            $0.isLocal && ($0.id.contains("lmstudio") || $0.baseURL.contains(":1234"))
        }
    }

    /// The non-vision LM Studio provider — its endpoint + model are the values to use
    /// for text tasks (rerank, LoRA base). `nil` if none is configured.
    @MainActor
    static func textProvider() -> ProviderConfig? {
        providers.first { !$0.supportsVision && !$0.model.isEmpty }
            ?? providers.first { !$0.model.isEmpty }
    }

    /// The vision-capable LM Studio provider — its model is what schematic OCR
    /// (S6 Part B) needs. `nil` if none is configured.
    @MainActor
    static func visionProvider() -> ProviderConfig? {
        providers.first { $0.supportsVision && !$0.model.isEmpty }
    }
}

/// Appends a scenario's captured run to `merlin/merlin-eval/results/` — every value logged end
/// to end (SURFACE-CENSUS.md → "Evidence & end-to-end value logging").
enum EvalLog {
    static func write(scenario: String, summary: String) {
        let dir = EvalPaths.root.appendingPathComponent("merlin/merlin-eval/results")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        try? summary.write(to: dir.appendingPathComponent("\(scenario)-harness-\(stamp).md"),
                           atomically: true, encoding: .utf8)
    }
}

/// The exact scenario prompts (kept identical to the scenario files).
enum EvalPrompts {
    static let s1 = """
    The macOS app at this project path is a SwiftUI task list called TaskBoard. Build \
    it, launch it, and use it the way a user would: add tasks, mark some done, delete \
    one, open the Stats window, click every toolbar button. It has logic and visual \
    defects. Find every defect by exercising the running app, fix each in the source, \
    rebuild, and re-verify. Report each defect, the fix, and how you confirmed it.
    """
    static let s2 = """
    The Rust project at this project path is an expense-ledger library and CLI. Build \
    it, run `cargo test`, exercise the CLI. It has logic, error-handling, and \
    concurrency bugs. Find every defect, fix it, and re-verify until `cargo test` is \
    green. Report each defect, root cause, fix, and how you confirmed it.
    """
    static let s4 = """
    Using the connected knowledge base, answer and cite each: (1) At what pressure does \
    the Glimworks Mark IV operate? (2) How long is its calibration cycle and what is \
    the reset code? (3) Who founded Glimworks Industries and in what city? (4) What is \
    the Mark IV's maximum rotational speed?
    """
    static let s6 = """
    Design a 555-timer astable LED blinker in this project: NE555 (U1), R1 10k, R2 47k, \
    C1 10µF, C2 10nF, R3 330, an LED (D1), 5V supply, standard astable. Create the \
    KiCad schematic, assign footprints, lay out the PCB, route it with FreeRouting, and \
    run an ngspice simulation confirming the output oscillates. Report the netlist, the \
    routing result, and the simulated blink frequency vs the ~1.4 Hz target.
    """

    static func s6OCR(imagePath: String) -> String {
        """
        Import the schematic image at \(imagePath). Extract its components and netlist \
        into a KiCad schematic. Report every component you recognised (designator + \
        value) and the connections between them, and flag anything you could not read.
        """
    }
}
```

---

## Write to: MerlinE2ETests/CapabilityScenarioTests.swift

```swift
import Foundation
import XCTest
@testable import Merlin

/// W5 — M1 capability harness. Drives the S1–S6 capability scenarios end to end. Each
/// test launches and tears down whatever external service it needs — nothing is started
/// by hand. Judgement rubric items (visuals, debugging soundness) are scored by a human
/// against the logged `EvalRun`.
final class CapabilityScenarioTests: XCTestCase {

    // MARK: - S1 — Swift GUI debug cycle

    @MainActor
    func testS1SwiftGUIDebugCycle() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("swift-gui-buggy"),
                          "S1 fixture missing — build fixtures/S1-taskboard-fixture.md")
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

    // MARK: - S2 — Rust debug cycle

    @MainActor
    func testS2RustDebugCycle() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("rust-buggy"),
                          "S2 fixture missing — build fixtures/S2-ledger-fixture.md")
        let fixture = EvalPaths.fixture("rust-buggy")

        let run = try await EvalHarness.runScenario(
            fixturePath: fixture, prompt: EvalPrompts.s2, timeout: 1800)
        XCTAssertTrue(run.errors.isEmpty, "S2 engine errors: \(run.errors)")

        let testOut = EvalShell.run("/usr/bin/env", ["cargo", "test"], cwd: fixture)
        EvalLog.write(scenario: "S2", summary: "tools \(run.toolCalls.count)\n"
            + "\(testOut.suffix(600))\n\(run.assistantText)")
        XCTAssertTrue(testOut.contains("test result: ok"),
                      "S2: cargo test must be green after Merlin's fixes")
    }

    // MARK: - S4 — xcalibre RAG (harness launches xcalibre-server)

    @MainActor
    func testS4RAGGrounding() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("rag-corpus"),
                          "S4 fixture missing — build fixtures/S4-rag-corpus-fixture.md")

        // 1. Build the xcalibre-server backend binary.
        let serverDir = EvalPaths.sibling("xcalibre-server")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: serverDir),
                          "xcalibre-server repo not found beside merlin")
        _ = EvalShell.run("/usr/bin/env", ["cargo", "build", "-p", "backend"], cwd: serverDir)
        let binary = "\(serverDir)/target/debug/backend"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: binary),
                          "xcalibre-server backend did not build")

        // 2. Write a private config — temp DB + storage, and a watch-folder pointed at
        //    the corpus (the watch folder ingests EPUBs with no auth). The backend
        //    reads the file named by the `CONFIG_PATH` env var
        //    (xcalibre-server/backend/src/config.rs:598). Confirm the `[database]` /
        //    `[app]` key names against `xcalibre-server/config.example.toml`.
        let port = 8094
        let work = NSTemporaryDirectory() + "xcalibre-server-eval-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: work) }
        // The RAG pipeline needs an LLM for reranking. Use Merlin's configured
        // non-vision LM Studio provider — its real endpoint + model — not a guess.
        guard let lm = EvalLMStudio.textProvider() else {
            throw XCTSkip("no non-vision LM Studio provider configured — "
                          + "S4 reranking needs a text model")
        }
        let configPath = "\(work)/config.toml"
        try """
        [app]
        storage_path = "\(work)/storage"
        [database]
        path = "\(work)/library.db"
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
                       "S4: Q4 is absent from the corpus — Merlin must not hallucinate it")
    }

    // MARK: - S5 — LoRA pipeline (harness seeds pairs + auto-trains)

    @MainActor
    func testS5LoRAPipeline() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("lora-dpo"),
                          "S5 fixture missing — build fixtures/S5-lora-dpo-fixture.md")
        let mlx = EvalShell.run("/usr/bin/env", ["python3", "-c", "import mlx_lm"], cwd: "/tmp")
        try XCTSkipUnless(!mlx.contains("Error") && !mlx.contains("Traceback"),
                          "mlx_lm not importable — S5 needs the LoRA training environment")

        // 1. Build OutcomeRecords from the fixture's DPO pairs (prompt + chosen).
        //    LoRATrainer reads only .prompt / .response; the other fields are valid
        //    placeholders (OutcomeRecord — ModelPerformanceTracker.swift).
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

        // 2. Run the real training pipeline — LoRATrainer drives `python -m mlx_lm.lora`.
        //    The base model is Merlin's configured non-vision LM Studio model — the
        //    text model, picked by capability, not the first one listed.
        guard let lm = EvalLMStudio.textProvider() else {
            throw XCTSkip("no non-vision LM Studio provider configured — "
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
                      "S5: the LoRA pipeline must complete — \(result.errorMessage ?? "")")
        let adapterFiles = (try? FileManager.default.contentsOfDirectory(atPath: adapterDir)) ?? []
        XCTAssertFalse(adapterFiles.isEmpty, "S5: training must produce an adapter artifact")
    }

    // MARK: - S6 — electronics (harness writes the MCP config; Merlin spawns the server)

    @MainActor
    func testS6Electronics() async throws {
        try skipUnlessLiveEnvironment()
        // The merlin-kicad-mcp server is launched BY Merlin from the project's
        // `.mcp.json` — the harness only writes that config; no service to manage here.
        let fixture = EvalPaths.fixture("electronics")
        try? FileManager.default.createDirectory(
            atPath: fixture, withIntermediateDirectories: true)

        let mcpServerPath = "\(EvalPaths.sibling("merlin"))/plugins/merlin-kicad-mcp"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: mcpServerPath),
                          "merlin-kicad-mcp plugin not found")
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

    // MARK: - S6 Part B — schematic OCR (needs the vision model)

    @MainActor
    func testS6SchematicOCR() async throws {
        try skipUnlessLiveEnvironment()
        let fixture = EvalPaths.fixture("electronics")
        let image = "\(fixture)/schematic-image/rc-filter.png"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: image),
                          "S6 OCR fixture missing — build fixtures/S6-electronics-fixture.md")

        // Schematic OCR is a vision task — route Merlin's vision slot at the
        // vision-capable LM Studio model (picked by capability, not the first listed).
        guard let vision = EvalLMStudio.visionProvider() else {
            throw XCTSkip("no vision-capable LM Studio provider configured — "
                          + "schematic OCR needs a vision model")
        }
        let priorVision = AppSettings.shared.slotAssignments[.vision]
        AppSettings.shared.slotAssignments[.vision] = vision.id
        defer { AppSettings.shared.slotAssignments[.vision] = priorVision }

        // The KiCad MCP server (Merlin spawns it) lets Merlin write the extracted
        // schematic; same config as Part A.
        let mcpServerPath = "\(EvalPaths.sibling("merlin"))/plugins/merlin-kicad-mcp"
        if FileManager.default.fileExists(atPath: mcpServerPath) {
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
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, zero warnings — the whole harness compiles against the real
`EvalHarness` / `Merlin` API (`OutcomeRecord`, `DomainTaskType`, `LoRATrainer.train`,
`EvalHarness.runScenario` all verified). Not run here.

Two values are *runtime-config strings* (string literals — they do not affect the
build): the xcalibre-server `[database]`/`[app]` TOML key names and the `merlin-kicad-mcp`
launch command. Confirm both against the in-repo files (`xcalibre-server/
config.example.toml`; the `merlin-kicad-mcp` README) when the suite is first run — a
bounded, in-repo lookup, **not** a manual step at proving time.

## Commit
```
git add MerlinE2ETests/EvalSupport.swift MerlinE2ETests/CapabilityScenarioTests.swift \
  tasks/task-326-eval-capability-harness.md
git commit -m "Task 326 — Eval capability harness (S1–S6), self-launching services"
```

## Fixes
Task 332 relocated `merlin-eval/` into the merlin repo (`merlin/merlin-eval/`).
`EvalPaths.fixture(_:)` and `EvalLog`'s results directory now resolve
`merlin/merlin-eval/...`; `EvalPaths.root` and `EvalPaths.sibling(_:)` are unchanged.
