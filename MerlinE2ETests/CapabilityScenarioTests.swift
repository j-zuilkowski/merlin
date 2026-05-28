import Foundation
import XCTest
@testable import Merlin

/// W5 - M1 capability harness. Drives the S1-S6 capability scenarios end to end. Each
/// test launches and tears down whatever external service it needs - nothing is started
/// by hand. Judgement rubric items (visuals, debugging soundness) are scored by a human
/// against the logged `EvalRun`.
final class CapabilityScenarioTests: XCTestCase {

    /// A fresh, pristine (git-committed) copy of a fixture in a temp directory.
    /// The S1/S2 debug scenarios mutate their fixture in place — Merlin edits the
    /// buggy sources to fix them — so running on the tracked fixture makes each run
    /// start from the previous run's leftover edits (or, after a failed run, from a
    /// half-broken tree with spurious files). That was a primary cause of S1/S2
    /// non-determinism. Running on a `git archive HEAD` extract makes each run start
    /// from the identical pristine baseline and never mutates the tracked fixture.
    /// The caller deletes the returned directory's parent.
    private static func pristineFixtureCopy(_ name: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)   // …/merlin/MerlinE2ETests/CapabilityScenarioTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().path
        let rel = "merlin-eval/fixtures/\(name)"
        let dest = NSTemporaryDirectory() + "eval-fixture-\(name)-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dest, withIntermediateDirectories: true)
        // `git --git-dir=`, NOT `git -C`: `-C` chdir's git into the repo, which
        // lives under ~/Documents, and git's startup `getcwd()` of that path
        // then wedges. The test-host app is rebuilt (new cdhash) every run, so
        // its TCC "Documents folder" grant is dropped each time; a `getcwd()`
        // directory-walk through ~/Documents blocks indefinitely on the
        // unanswered TCC check (proven via lsof: the wedged git's cwd was the
        // repo). `--git-dir` reads the object DB without chdir'ing, so git's
        // cwd stays in the temp `dest` dir — a /private/var/folders path that
        // needs no TCC. zsh's cwd is `dest` for the same reason.
        let out = EvalShell.run("/bin/zsh", ["-c",
            "git --git-dir='\(repoRoot)/.git' archive HEAD '\(rel)' | tar -x -C '\(dest)'"],
            cwd: dest)
        let copied = "\(dest)/\(rel)"
        guard FileManager.default.fileExists(atPath: copied) else {
            throw XCTSkip("could not extract pristine fixture '\(name)': \(out)")
        }
        try seedProjectConfigIfNeeded(fixtureName: name, fixturePath: copied)
        try initializeFixtureGitRepository(fixturePath: copied)
        return copied
    }

    private static func initializeFixtureGitRepository(fixturePath: String) throws {
        let steps: [(String, [String])] = [
            ("/usr/bin/git", ["init"]),
            ("/usr/bin/git", ["config", "user.email", "merlin-eval@example.invalid"]),
            ("/usr/bin/git", ["config", "user.name", "Merlin Eval"]),
            ("/usr/bin/git", ["add", "."]),
            ("/usr/bin/git", ["commit", "-m", "fixture baseline"])
        ]
        for (launchPath, args) in steps {
            let output = EvalShell.run(launchPath, args, cwd: fixturePath, timeout: 120)
            if output.contains("EvalShell launch error") || output.contains("EvalShell timeout") {
                throw NSError(
                    domain: "CapabilityScenarioTests",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "could not initialize fixture git repository: \(output)"
                    ]
                )
            }
        }
        let head = EvalShell.run(
            "/usr/bin/git", ["rev-parse", "--verify", "HEAD"],
            cwd: fixturePath, timeout: 120)
        guard FileManager.default.fileExists(atPath: "\(fixturePath)/.git"),
              !head.contains("fatal:") else {
            throw NSError(
                domain: "CapabilityScenarioTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "fixture git repository has no committed HEAD: \(head)"
                ]
            )
        }
    }

    private static func seedProjectConfigIfNeeded(fixtureName: String,
                                                  fixturePath: String) throws {
        let adapter: String?
        switch fixtureName {
        case "swift-gui-buggy":
            adapter = "swift-xcode"
        case "rust-buggy":
            adapter = "rust-cargo"
        default:
            adapter = nil
        }

        guard let adapter else { return }
        let configURL = URL(fileURLWithPath: fixturePath)
            .appendingPathComponent(".merlin")
            .appendingPathComponent("project.toml")
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        adapter = "\(adapter)"
        adapter_version = "1.0"
        discipline_layers = ["soft_prompt", "pre_commit"]
        manual_coverage_baseline = 0
        decay_per_release = 10

        """.write(to: configURL, atomically: true, encoding: .utf8)
    }

    // MARK: - S1 - Swift GUI debug cycle

    @MainActor
    func testS1SwiftGUIDebugCycle() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("swift-gui-buggy"),
                          "S1 fixture missing - build fixtures/S1-taskboard-fixture.md")
        // Run on a pristine extract — Merlin edits the buggy sources, so reusing the
        // tracked fixture would carry a prior run's edits into this one.
        let fixture = try Self.pristineFixtureCopy("swift-gui-buggy")
        defer { try? FileManager.default.removeItem(
            atPath: URL(fileURLWithPath: fixture).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().path) }

        let run = try await EvalHarness.runScenario(
            fixturePath: fixture, prompt: EvalPrompts.s1, timeout: 1800)
        XCTAssertTrue(run.errors.isEmpty, "S1 engine errors: \(run.errors)")

        _ = EvalShell.run("/usr/bin/xcodegen", ["generate"], cwd: fixture)
        let testOut = EvalShell.run("/usr/bin/xcodebuild",
            ["-scheme", "TaskBoard", "test", "-destination", "platform=macOS",
             "CODE_SIGN_IDENTITY=", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO"],
            cwd: fixture)
        // DIAGNOSTIC: capture the critic's activity — did it run the xcodebuild
        // verification and catch the red TaskBoardTests, and how many retries?
        let criticEvents = run.allEvents.compactMap { event -> String? in
            if case .systemNote(let n) = event,
               n.lowercased().contains("critic") || n.lowercased().contains("unverified") {
                return n
            }
            return nil
        }
        EvalLog.write(scenario: "S1", summary: "tools \(run.toolCalls.count) "
            + "errors \(run.errors.count)\n"
            + "--- critic/systemNotes ---\n\(run.systemNotes.joined(separator: "\n"))\n"
            + "--- critic events ---\n\(criticEvents.joined(separator: "\n"))\n"
            + "--- xcodebuild test ---\n\(testOut.suffix(600))\n\(run.assistantText)")
        let status = CapabilityConvergenceClassifier().classify(
            verificationOutput: testOut,
            assistantText: run.assistantText)
        XCTAssertEqual(status, .green,
                       "S1: TaskBoardTests must pass after Merlin's fixes; status \(status)")
    }

    // MARK: - S2 - Rust debug cycle

    @MainActor
    func testS2RustDebugCycle() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("rust-buggy"),
                          "S2 fixture missing - build fixtures/S2-ledger-fixture.md")
        // Run on a pristine extract — Merlin edits the buggy sources, so reusing the
        // tracked fixture would carry a prior run's edits into this one.
        let fixture = try Self.pristineFixtureCopy("rust-buggy")
        defer { try? FileManager.default.removeItem(
            atPath: URL(fileURLWithPath: fixture).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().path) }

        let run = try await EvalHarness.runScenario(
            fixturePath: fixture, prompt: EvalPrompts.s2, timeout: 1800)
        XCTAssertTrue(run.errors.isEmpty, "S2 engine errors: \(run.errors)")

        // Run via `zsh -c` (sources the user's env) — `/usr/bin/env` execs with the
        // test process's minimal PATH, which lacks `~/.cargo/bin`, so `cargo` is unfound.
        let testOut = EvalShell.run("/bin/zsh", ["-c", "cargo test"], cwd: fixture)
        EvalLog.write(scenario: "S2", summary: "tools \(run.toolCalls.count)\n"
            + "\(testOut.suffix(600))\n\(run.assistantText)")
        let status = CapabilityConvergenceClassifier().classify(
            verificationOutput: testOut,
            assistantText: run.assistantText)
        XCTAssertEqual(status, .green,
                       "S2: cargo test must be green after Merlin's fixes; status \(status)")
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
        guard EvalLMStudio.ensureServerRunning() else {
            XCTFail("LM Studio server did not become ready at http://localhost:1234/v1/models")
            return
        }
        EvalLMStudio.ensureModelLoaded(lm.model)
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
        let serverLog = "\(work)/xcalibre-server.log"
        try server.launch(executable: binary, cwd: serverDir,
                          env: ["CONFIG_PATH": configPath,
                                "APP_BIND_ADDR": "127.0.0.1:\(port)"],
                          logPath: serverLog)
        defer { server.terminate() }
        let ready = await server.waitUntilReady(
            url: "http://127.0.0.1:\(port)/api/docs/openapi.json", timeout: 120)
        guard ready else {
            XCTFail("xcalibre-server did not become ready\n\(Self.tail(serverLog))")
            return
        }
        // 3. Register the first user (auto-promoted to admin on a fresh install) and
        //    log in to obtain a JWT. The xcalibre-server search endpoints require
        //    auth, so Merlin's XcalibreClient needs a real bearer token — an empty
        //    token makes it short-circuit every search to an empty result.
        let base = "http://127.0.0.1:\(port)"
        let token = try await Self.bootstrapXcalibreAdminToken(baseURL: base)
        let priorXcalibreURL = AppSettings.shared.kagXcalibreURL
        let priorXcalibreToken = AppSettings.shared.xcalibreToken
        AppSettings.shared.kagXcalibreURL = base
        AppSettings.shared.xcalibreToken = token
        setenv("XCALIBRE_BASE_URL", base, 1)
        setenv("XCALIBRE_TOKEN", token, 1)
        defer {
            AppSettings.shared.kagXcalibreURL = priorXcalibreURL
            AppSettings.shared.xcalibreToken = priorXcalibreToken
            unsetenv("XCALIBRE_BASE_URL")
            unsetenv("XCALIBRE_TOKEN")
        }

        // Wait for the watch-folder to ingest both corpus EPUBs (file stored, book
        // row inserted, search chunks generated) before the scenario runs — the
        // first RAG query must have data to retrieve.
        let ingestedCount = await Self.waitForWatchFolderIngest(
            baseURL: base, token: token, expected: 2, timeoutSeconds: 120)
        guard ingestedCount == 2 else {
            XCTFail("xcalibre-server watch-folder must ingest both corpus EPUBs "
                    + "(got \(ingestedCount))\n\(Self.tail(serverLog))")
            return
        }
        let ragFactsReady = await Self.waitForRAGFacts(
            baseURL: base, token: token, timeoutSeconds: 120)
        guard ragFactsReady else {
            XCTFail("xcalibre-server chunk search must return the seeded S4 facts "
                    + "before Merlin's agentic RAG scenario starts\n\(Self.tail(serverLog))")
            return
        }

        let run = try await EvalHarness.runScenario(
            fixturePath: EvalPaths.fixture("rag-corpus"),
            prompt: EvalPrompts.s4, timeout: 900)

        EvalLog.write(scenario: "S4", summary: "errors \(run.errors.count)\n\(run.assistantText)")
        guard server.isRunning else {
            XCTFail("xcalibre-server exited during S4 scenario\n\(Self.tail(serverLog))")
            return
        }
        let answer = run.assistantText.lowercased()
        XCTAssertTrue(answer.contains("47") && answer.contains("tangerine"),
                      "S4: grounded facts (47 kPa, TANGERINE-7) must be retrieved\n"
                      + "\(Self.tail(serverLog))")
        // Q4 (max rotational speed) is absent from the corpus — Merlin must not
        // fabricate it. The model SHOULD still name the topic when correctly
        // declining ("rotational speed: not found … no results for RPM"), so a
        // bare substring check on "rotational speed"+"rpm" false-positives on the
        // *desired* behaviour. Assert instead that no numeric RPM *value* is
        // stated: a digit immediately qualifying "rpm". A correct refusal has no
        // digit before "rpm"; a hallucination ("8,000 rpm") trips it — still strict.
        let fabricatedRPM = answer.range(
            of: #"\d[\d,.]*\s*rpm"#, options: .regularExpression) != nil
        XCTAssertFalse(fabricatedRPM,
                       "S4: Q4 is absent from the corpus - Merlin must not state a "
                       + "fabricated rotational-speed value (answer: \(answer.prefix(300)))")
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
        //    text model, picked by capability, not the first one listed. mlx_lm needs
        //    the model's on-disk MLX directory, not the LM Studio alias.
        guard let lm = EvalLMStudio.textProvider() else {
            throw XCTSkip("no non-vision LM Studio provider configured - "
                          + "S5 needs a text base model")
        }
        guard let baseModelPath = EvalLMStudio.localModelDirectory(forModelID: lm.model) else {
            throw XCTSkip("could not resolve LM Studio model '\(lm.model)' to a local "
                          + "MLX model directory - S5 needs a path mlx_lm can load")
        }
        // mlx_lm loads the base model into memory; on a machine where LM Studio
        // already holds large models the two collide on RAM and LM Studio evicts its
        // loaded models, corrupting every later scenario. Free LM Studio's memory for
        // the trainer and restore exactly what was loaded afterwards.
        let lmStudioLoaded = EvalLMStudio.loadedModels()
        EvalLMStudio.unloadAllModels()
        defer { EvalLMStudio.loadModels(lmStudioLoaded) }

        let adapterDir = NSTemporaryDirectory() + "merlin-lora-adapter-\(UUID())"
        let result = await LoRATrainer().train(
            records: records,
            baseModel: baseModelPath,
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

    // MARK: - S6 - electronics (Merlin loads the first-party electronics plugin)

    @MainActor
    func testS6Electronics() async throws {
        try skipUnlessLiveEnvironment()
        // S6 builds a KiCad project from scratch. Run it in a freshly-wiped
        // workspace: a prior run leaves .kicad_sch/.kicad_pcb directories behind in
        // the fixture, and the model then `list_directory`s the root, finds an
        // existing 555-blinker project, declares the task already done, and never
        // calls the KiCad tools. Wiping the workspace each run removes that
        // short-circuit — it was a primary cause of S6's non-determinism.
        let workspace = "\(EvalPaths.fixture("electronics"))/s6-workspace"
        try? FileManager.default.removeItem(atPath: workspace)
        try FileManager.default.createDirectory(
            atPath: workspace, withIntermediateDirectories: true)

        let run = try await EvalHarness.runScenario(
            fixturePath: workspace,
            prompt: EvalPrompts.s6,
            timeout: 1800,
            activeDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID])
        EvalLog.write(scenario: "S6", summary: "tools \(run.toolCalls.count) "
            + "errors \(run.errors.count)\n\(run.assistantText)")
        let failedTools = run.toolCalls.filter(\.isError)
        let failedToolSummary = failedTools.map { call in
            let result = call.result ?? "<no result>"
            return "\(call.name) args=\(call.arguments.prefix(500)) result=\(result.prefix(500))"
        }.joined(separator: "\n")
        XCTAssertTrue(failedTools.isEmpty,
                      "S6: electronics tools must not fail:\n\(failedToolSummary)")
        XCTAssertTrue(run.toolCalls.contains { $0.name.hasPrefix("kicad_") || $0.name.hasPrefix("workflow.") },
                      "S6: Merlin must call the first-party KiCad/electronics tools")
        let workflowReport = run.toolCalls
            .filter { $0.name == "workflow.requirements_to_pcb" || $0.name == "workflow.schematic_to_pcb" }
            .compactMap { call -> ElectronicsFinalReport? in
                guard let result = call.result else { return nil }
                return try? WorkspaceJSON.decoder.decode(ElectronicsFinalReport.self, from: Data(result.utf8))
            }
            .last
        XCTAssertEqual(workflowReport?.status, .complete,
                       "S6: workflow must finish with a complete electronics final report")
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
        // Slot assignments are "<provider>:<model>". vision.id alone is just the
        // provider ("lmstudio") — that leaves the vision call with no model, so OCR
        // never reaches qwen3-vl-8b. Assign the full provider:model pair.
        AppSettings.shared.slotAssignments[.vision] = "\(vision.id):\(vision.model)"
        defer { AppSettings.shared.slotAssignments[.vision] = priorVision }
        // Make the vision model resident so the OCR call does not burn the
        // scenario's time budget on a cold JIT load.
        EvalLMStudio.ensureModelLoaded(vision.model)

        let run = try await EvalHarness.runScenario(
            fixturePath: fixture,
            prompt: EvalPrompts.s6OCR(imagePath: image),
            timeout: 900,
            activeDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID])

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

    // MARK: - S4 helpers

    private enum S4Error: Error { case message(String) }

    private static func tail(_ path: String, maxBytes: Int = 16_384) -> String {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return "(no xcalibre-server log at \(path))"
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "(xcalibre-server log was not utf8)"
    }

    /// Registers the first xcalibre-server user (auto-promoted to admin on a fresh
    /// install) and logs in, returning the JWT access token.
    private static func bootstrapXcalibreAdminToken(baseURL: String) async throws -> String {
        let username = "evaladmin"
        let password = "EvalPass123!"
        _ = try await postJSON(
            url: "\(baseURL)/api/v1/auth/register",
            body: ["username": username, "email": "eval@merlin.test", "password": password])
        let login = try await postJSON(
            url: "\(baseURL)/api/v1/auth/login",
            body: ["username": username, "password": password])
        guard let token = login["access_token"] as? String, !token.isEmpty else {
            throw S4Error.message("xcalibre-server login returned no access_token")
        }
        return token
    }

    /// Polls the watch-folder log until `expected` files reach a terminal status,
    /// returning the count that were successfully ingested.
    private static func waitForWatchFolderIngest(
        baseURL: String, token: String, expected: Int, timeoutSeconds: Int
    ) async -> Int {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if let log = try? await getJSON(
                url: "\(baseURL)/api/v1/admin/watch-folder/log", token: token),
               let items = log["items"] as? [[String: Any]] {
                let statuses = items.compactMap { $0["status"] as? String }
                let terminal = statuses.filter { $0 != "pending" }
                if terminal.count >= expected {
                    return terminal.filter { $0 == "ingested" }.count
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return 0
    }

    /// Polls the same authenticated chunk-search endpoint that Merlin's
    /// XcalibreClient uses. Watch-folder "ingested" means rows/chunks were written,
    /// but the first retrieval can still race search readiness; S4 should not hand
    /// that transient state to the agent and misreport it as a reasoning failure.
    private static func waitForRAGFacts(
        baseURL: String, token: String, timeoutSeconds: Int
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        let queries = [
            "Glimworks Mark IV pressure",
            "TANGERINE-7 calibration cycle",
            "Glimworks founder city"
        ]
        while Date() < deadline {
            var combined = ""
            for query in queries {
                guard let url = chunkSearchURL(baseURL: baseURL, query: query) else {
                    continue
                }
                if let search = try? await getJSON(url: url, token: token),
                   let chunks = search["chunks"] as? [[String: Any]] {
                    combined += " " + chunks.compactMap { $0["text"] as? String }
                        .joined(separator: " ")
                }
            }
            let lower = combined.lowercased()
            if lower.contains("47") && lower.contains("tangerine-7")
                && lower.contains("glimworks") {
                return true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return false
    }

    private static func chunkSearchURL(baseURL: String, query: String) -> String? {
        guard var components = URLComponents(string: "\(baseURL)/api/v1/search/chunks") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "source", value: "books"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "rerank", value: "false")
        ]
        return components.url?.absoluteString
    }

    private static func postJSON(url: String, body: [String: Any]) async throws -> [String: Any] {
        guard let endpoint = URL(string: url) else { throw S4Error.message("bad URL \(url)") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func getJSON(url: String, token: String) async throws -> [String: Any] {
        guard let endpoint = URL(string: url) else { throw S4Error.message("bad URL \(url)") }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
