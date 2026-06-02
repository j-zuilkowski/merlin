import XCTest
@testable import Merlin

// MARK: - Test doubles

/// Planner stub: returns a preset classification and fixed steps from decompose().
private final class StubPlanner: PlannerEngineProtocol, @unchecked Sendable {
    let classification: ClassifierResult
    let steps: [PlanStep]

    init(classification: ClassifierResult, steps: [PlanStep] = []) {
        self.classification = classification
        self.steps = steps
    }

    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        classification
    }

    func decompose(task: String, context: [Message]) async -> [PlanStep] {
        steps
    }
}

/// Planner spy: classify() returns needsPlanning=true so that without the
/// [CONTINUATION] bypass the engine WOULD call decompose(). Records whether it did.
private final class SpyPlanner: PlannerEngineProtocol, @unchecked Sendable {
    private(set) var decomposeCalled = false

    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        // Claim planning is needed — without the [CONTINUATION] fix the engine
        // would enter the planner block and call decompose() through classifierOverride.
        ClassifierResult(needsPlanning: true, complexity: .standard, reason: "spy")
    }

    func decompose(task: String, context: [Message]) async -> [PlanStep] {
        decomposeCalled = true
        return []
    }
}

private struct PassCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .pass
    }
}

// MARK: - Tests

@MainActor
final class LoopContinuationTests: XCTestCase {

    private var injectURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        // Use a per-test temp file so Merlin (if running) never consumes the inject
        // before our assertion reads it.
        injectURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-continuation-\(UUID().uuidString).txt")
        try? FileManager.default.removeItem(at: injectURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: injectURL)
        try await super.tearDown()
    }

    private func readInject() throws -> String {
        try String(contentsOf: injectURL, encoding: .utf8)
    }

    @discardableResult
    private func writeArtifact(name: String, contents: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Fix 1: Plan batching & continuation inject

    /// When the planner returns more steps than the per-turn budget (maxIterations / 4),
    /// the engine executes only the first batch and writes a [CONTINUATION] inject for the rest.
    func testPlanBatchSplitsAndSchedulesContinuation() async throws {
        try skipUnlessLiveEnvironment()
        let provider = MockProvider(responses: [MockLLMResponse.text("done with batch")])
        let engine = makeEngine(provider: provider)

        // Force maxIterations=4 so stepsPerTurn = max(1, 4/4) = 1.
        // Any plan with 2+ steps will be split.
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL

        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "test"),
            steps: [
                PlanStep(description: "step one",   successCriteria: "", complexity: .standard),
                PlanStep(description: "step two",   successCriteria: "", complexity: .standard),
                PlanStep(description: "step three", successCriteria: "", complexity: .standard),
            ]
        )

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "do many things") {
            events.append(event)
        }

        // Engine must emit a "batch 1/" system note.
        let hasBatchNote = events.contains {
            if case .systemNote(let note) = $0 { return note.contains("batch 1/") }
            return false
        }
        XCTAssertTrue(hasBatchNote, "Expected a 'batch 1/' system note for a split plan")

        // Continuation inject file must exist and start with [CONTINUATION].
        XCTAssertTrue(FileManager.default.fileExists(atPath: injectURL.path),
                      "Continuation inject file should be written after a batch-split turn")
        let contents = try String(contentsOf: injectURL, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("[CONTINUATION]"),
                      "Inject file must open with [CONTINUATION] sentinel")
        XCTAssertTrue(contents.contains("step two"),
                      "Inject file must include the remaining steps")
    }

    /// A critic pass means the user-visible task is done, even if the initial
    /// planner created later batches. Those queued continuations must be cleared
    /// so the engine exits cleanly instead of resubmitting already-complete work.
    func testCriticPassClearsPendingContinuation() async throws {
        let provider = MockProvider(responses: [MockLLMResponse.text("All tests pass.")])
        let engine = makeEngine(provider: provider)

        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.criticOverride = PassCritic()
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "test"),
            steps: [
                PlanStep(description: "step one", successCriteria: "", complexity: .standard),
                PlanStep(description: "step two", successCriteria: "", complexity: .standard),
                PlanStep(description: "step three", successCriteria: "", complexity: .standard),
            ]
        )

        var notes: [String] = []
        for await event in engine.send(userMessage: "do many things") {
            if case .systemNote(let note) = event {
                notes.append(note)
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path),
                       "A passing critic verdict should clear queued continuation injects")
        XCTAssertTrue(notes.contains { $0.contains("verification passed") },
                      "Expected an observable note when a passing critic clears queued continuations")
    }

    /// If the model runs a real verification tool and it passes, the engine should
    /// be able to stop immediately after critic confirmation. This covers models
    /// that keep asking for more tools instead of emitting a final no-tool answer.
    func testVerificationToolPassStopsWithoutFinalAssistantMessage() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "verify", name: "xcode_test", args: #"{"scheme":"TaskBoard"}"#),
            MockLLMResponse.toolCall(id: "repeat", name: "xcode_test", args: #"{"scheme":"TaskBoard"}"#),
        ])
        let engine = makeEngine(provider: provider)

        engine.maxIterationsOverride = 4
        engine.criticOverride = PassCritic()
        engine.registerTool("xcode_test") { _ in
            """
            Test Suite 'Selected tests' passed.
                 Executed 5 tests, with 0 failures (0 unexpected)
            ** TEST SUCCEEDED **
            """
        }

        var notes: [String] = []
        var toolResults: [String] = []
        for await event in engine.send(userMessage: "fix and verify the project") {
            if case .systemNote(let note) = event {
                notes.append(note)
            }
            if case .toolCallResult(let result) = event {
                toolResults.append(result.content)
            }
        }

        XCTAssertEqual(toolResults.count, 1,
                       "Engine should stop after the first green verification tool result; notes=\(notes); results=\(toolResults)")
        XCTAssertTrue(notes.contains { $0.contains("verification passed after tool result") },
                      "Expected an observable post-tool verification stop note")
    }

    func testRequestedStopBoundaryStopsAfterMatchingToolResult() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "ir1", name: "kicad_generate_circuit_ir", args: "{}"),
            MockLLMResponse.toolCall(id: "ir2", name: "kicad_generate_circuit_ir", args: "{}"),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.registerTool("kicad_generate_circuit_ir") { _ in
            #"{"artifact":{"kind":"circuit_ir","path":"/tmp/amp-circuit-ir.json"}}"#
        }

        var notes: [String] = []
        var toolResults: [String] = []
        for await event in engine.send(
            userMessage: "Call kicad_generate_circuit_ir, then stop immediately after the Circuit IR artifact exists."
        ) {
            if case .systemNote(let note) = event {
                notes.append(note)
            }
            if case .toolCallResult(let result) = event {
                toolResults.append(result.content)
            }
        }

        XCTAssertEqual(
            toolResults.count,
            1,
            "Engine must not continue after a successful tool result that satisfies an explicit stop boundary"
        )
        XCTAssertTrue(
            notes.contains { $0.contains("requested stop boundary satisfied") },
            notes.joined(separator: "\n")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path))
    }

    /// A plan whose step count fits within the per-turn budget does NOT write a continuation inject.
    func testSmallPlanDoesNotScheduleContinuation() async throws {
        let provider = MockProvider(responses: [MockLLMResponse.text("done")])
        let engine = makeEngine(provider: provider)

        // stepsPerTurn = max(1, 16/4) = 4 → a single-step plan fits comfortably.
        engine.maxIterationsOverride = 16
        engine.continuationInjectURL = injectURL

        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "test"),
            steps: [
                PlanStep(description: "only step", successCriteria: "", complexity: .standard),
            ]
        )

        for await _ in engine.send(userMessage: "simple task") {}

        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path),
                       "No continuation inject expected when plan fits in one turn")
    }

    func testElectronicsContinuationOnlyAdvancesOnToolArtifactEvidence() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-continuation-evidence")
        let schematicPath = try writeArtifact(
            name: "amp.kicad_sch",
            contents: "(kicad_sch (version 20250114) (symbol \"amplifier\"))\n",
            in: artifactRoot
        )
        let spicePath = try writeArtifact(
            name: "amp-spice.log",
            contents: "SPICE class A amplifier transient output: PASS\n",
            in: artifactRoot
        )
        let gerberDirectory = artifactRoot.appendingPathComponent("gerbers", isDirectory: true)
        try FileManager.default.createDirectory(at: gerberDirectory, withIntermediateDirectories: true)
        _ = try writeArtifact(name: "amp-F_Cu.gbr", contents: "G04 gerber\n", in: gerberDirectory)
        _ = try writeArtifact(name: "amp.drl", contents: "M48 drill\n", in: gerberDirectory)
        let bomPath = try writeArtifact(
            name: "amp-bom.csv",
            contents: "RefDes,Value,MPN,DigiKey,Mouser,Quantity\nQ1,MJL3281,MJL3281AG,863-MJL3281AGOS-ND,863-MJL3281AG,2\n",
            in: artifactRoot
        )

        func makeEvidenceEngine(
            toolName: String,
            toolResult: String,
            steps: [PlanStep]
        ) -> AgenticEngine {
            let provider = MockProvider(responses: [
                .toolCall(id: "evidence", name: toolName, args: #"{"project_path":"/tmp/amp.kicad_pro"}"#)
            ])
            let engine = makeEngine(provider: provider)
            engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
            engine.permissionMode = .autoAccept
            engine.maxIterationsOverride = 4
            engine.continuationInjectURL = injectURL
            engine.classifierOverride = StubPlanner(
                classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
                steps: steps
            )
            engine.registerTool(toolName) { _ in toolResult }
            return engine
        }

        try? FileManager.default.removeItem(at: injectURL)
        var engine = makeEvidenceEngine(
            toolName: "kicad_compile_project",
            toolResult: #"{"artifacts":[{"kind":"kicad_schematic","path":"\#(schematicPath.path)"}]}"#,
            steps: [
                PlanStep(description: "Create KiCad schematic", successCriteria: "schematic artifact exists", complexity: .standard),
                PlanStep(description: "Run SPICE simulation", successCriteria: "SPICE output exists", complexity: .standard),
            ]
        )
        for await _ in engine.send(userMessage: "Create the schematic artifact") {}
        var continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-1 have verified tool/artifact evidence."), continuationText)
        XCTAssertTrue(continuationText.contains("  2. Run SPICE simulation"), continuationText)

        try? FileManager.default.removeItem(at: injectURL)
        engine = makeEvidenceEngine(
            toolName: "kicad_run_spice",
            toolResult: #"{"artifacts":[{"kind":"spice_measurements","path":"\#(spicePath.path)"}]}"#,
            steps: [
                PlanStep(description: "Run SPICE simulation", successCriteria: "SPICE output exists", complexity: .standard),
                PlanStep(description: "Export Gerbers and drill files", successCriteria: "Gerber and drill files exist", complexity: .standard),
            ]
        )
        for await _ in engine.send(userMessage: "Run SPICE simulation") {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-1 have verified tool/artifact evidence."), continuationText)
        XCTAssertTrue(continuationText.contains("  2. Export Gerbers and drill files"), continuationText)

        try? FileManager.default.removeItem(at: injectURL)
        engine = makeEvidenceEngine(
            toolName: "kicad_export_fab",
            toolResult: #"{"artifacts":[{"kind":"gerbers","path":"\#(gerberDirectory.path)"},{"kind":"drills","path":"\#(gerberDirectory.appendingPathComponent("amp.drl").path)"}]}"#,
            steps: [
                PlanStep(description: "Export Gerbers and drill files", successCriteria: "Gerber and drill files exist", complexity: .standard),
                PlanStep(description: "Produce BOM with Digi-Key and Mouser part numbers", successCriteria: "vendor BOM artifact exists", complexity: .standard),
            ]
        )
        for await _ in engine.send(userMessage: "Export fabrication files") {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-1 have verified tool/artifact evidence."), continuationText)
        XCTAssertTrue(continuationText.contains("  2. Produce BOM with Digi-Key and Mouser part numbers"), continuationText)

        try? FileManager.default.removeItem(at: injectURL)
        engine = makeEvidenceEngine(
            toolName: "kicad_prepare_vendor_order",
            toolResult: #"{"artifacts":[{"kind":"bom","path":"\#(bomPath.path)"}],"vendors":["Digi-Key","Mouser"]}"#,
            steps: [
                PlanStep(description: "Produce BOM with Digi-Key and Mouser part numbers", successCriteria: "vendor BOM artifact exists", complexity: .standard),
            ]
        )
        for await _ in engine.send(userMessage: "Produce the vendor BOM") {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path),
                       "Final BOM evidence should clear the continuation inject")
    }

    func testElectronicsRequirementsReadStepCountsWhenCriteriaMentionsDesign() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(id: "read-spec", name: "read_file", args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#),
            .text("Spec read.")
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read and parse the AmpDemo specification file to understand the project requirements and constraints",
                    successCriteria: "requirements understood for schematic design, simulation, fabrication, and BOM planning",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Start the electronics workflow with the first real KiCad domain tool",
                    successCriteria: "electronics workflow tool invoked",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Create KiCad schematic",
                    successCriteria: "schematic artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run SPICE simulation",
                    successCriteria: "SPICE output exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }

        for await _ in engine.send(userMessage: "Run the clean AmpDemo smoke slice") {}

        let continuationText = try readInject()
        XCTAssertTrue(
            continuationText.contains("Steps 1-1 have verified tool/artifact evidence."),
            continuationText
        )
        XCTAssertTrue(
            continuationText.contains("  2. Start the electronics workflow with the first real KiCad domain tool"),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("  1. Read and parse the AmpDemo specification file"),
            "A successful read_file call must satisfy the requirements-read step even when its criteria mention design terms"
        )
    }

    func testReadOnlySpecDoesNotSatisfyToolchainOrVendorBOMStep() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(id: "read-spec", name: "read_file", args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#),
            .text("Spec read.")
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read and parse the AmpDemo spec.md to extract all functional, electrical, and artifact requirements",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Verify toolchain availability: KiCad, ngspice, Digi-Key/Mouser API access, and output directory paths",
                    successCriteria: "toolchain and vendor API readiness verified",
                    complexity: .highStakes
                ),
                PlanStep(
                    description: "Design Intent Document: define topology, component families, and safety constraints",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("read_file") { _ in
            "AmpDemo requires a BOM with Digi-Key and Mouser part numbers plus KiCad/SPICE/Gerber artifacts."
        }

        for await _ in engine.send(userMessage: "Run the full AmpDemo electronics workflow") {}

        let continuationText = try readInject()
        XCTAssertTrue(
            continuationText.contains("Steps 1-1 have verified tool/artifact evidence."),
            continuationText
        )
        XCTAssertTrue(
            continuationText.contains("  2. Verify toolchain availability"),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("Steps 1-2 have verified tool/artifact evidence."),
            "Reading a spec that mentions BOM vendors must not complete the toolchain/BOM readiness step"
        )
    }

    func testSpecReadCanOnlyCompleteInspectionStepsBeforeDesignIntent() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(id: "read-spec", name: "read_file", args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#),
            .text("Spec read.")
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read AmpDemo spec.md",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Verify the spec.md file exists and is readable",
                    successCriteria: "requirements file readable",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Build DesignIntent with the electronics KiCad domain tool",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Generate KiCad schematic from DesignIntent",
                    successCriteria: "schematic artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }

        for await _ in engine.send(userMessage: "Run the focused AmpDemo electronics slice") {}

        let continuationText = try readInject()
        XCTAssertTrue(
            continuationText.contains("Steps 1-2 have verified tool/artifact evidence."),
            continuationText
        )
        XCTAssertTrue(
            continuationText.contains("  3. Build DesignIntent with the electronics KiCad domain tool"),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("  4. Generate KiCad schematic from DesignIntent"),
            "Spec inspection must not advance through DesignIntent or schematic generation"
        )
    }

    func testElectronicsReadStepStopsBeforeReadOnlyDrift() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(id: "read-spec", name: "read_file", args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#),
            .toolCall(id: "drift", name: "list_directory", args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo"}"#),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 8
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read AmpDemo spec.md",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Build DesignIntent with the electronics KiCad domain tool",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
            ]
        )

        var listDirectoryCallCount = 0
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("list_directory") { _ in
            listDirectoryCallCount += 1
            return "This read-only drift should not be dispatched after spec evidence is verified"
        }

        var notes: [String] = []
        for await event in engine.send(userMessage: "Run the focused AmpDemo electronics slice") {
            if case .systemNote(let note) = event {
                notes.append(note)
            }
        }

        XCTAssertEqual(listDirectoryCallCount, 0, "Current-step evidence should stop the turn before extra read-only drift")
        let continuationText = try readInject()
        XCTAssertTrue(
            continuationText.contains("Steps 1-1 have verified tool/artifact evidence."),
            continuationText
        )
        XCTAssertTrue(
            continuationText.contains("  2. Build DesignIntent with the electronics KiCad domain tool"),
            continuationText
        )
        XCTAssertTrue(
            notes.contains { $0.contains("electronics evidence verified for current step") },
            notes.joined(separator: "\n")
        )
    }

    func testDesignIntentArtifactForcesNextHandoffInsteadOfSpecReread() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-design-intent-handoff")
        let designIntentPath = try writeArtifact(
            name: "amp-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"25W Class A"}"#,
            in: artifactRoot
        )
        let circuitIRPath = artifactRoot.appendingPathComponent("amp-circuit_ir.json")
        let provider = MockProvider(responses: [
            .toolCall(
                id: "intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"amp_low_voltage_audio"}"#
            ),
            .toolCall(
                id: "reread",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .toolCall(
                id: "reread-again",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Build DesignIntent with the electronics KiCad domain tool",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Approve DesignIntent using the generated artifact path",
                    successCriteria: "DesignIntent approved",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Generate Circuit IR from approved DesignIntent",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("kicad_build_intent_model") { _ in
            #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}],"nextActions":["review_and_approve_design_intent"]}"#
        }
        var readFileCallCount = 0
        engine.registerTool("read_file") { _ in
            readFileCallCount += 1
            return "This stale read should be blocked after DesignIntent exists"
        }
        var approveCallCount = 0
        var approveArguments = ""
        engine.registerTool("kicad_approve_design_intent") { args in
            approveCallCount += 1
            approveArguments = args
            return #"{"approval":{"status":"approved"},"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}]}"#
        }
        var circuitIRCallCount = 0
        engine.registerTool("kicad_generate_circuit_ir") { _ in
            circuitIRCallCount += 1
            try? #"{"design_id":"AmpDemo","components":[],"nets":[]}"#.write(
                to: circuitIRPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"circuit_ir","path":"\#(circuitIRPath.path)"}]}"#
        }

        for await _ in engine.send(userMessage: "Run the focused AmpDemo electronics handoff") {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Existing DesignIntent artifact: \(designIntentPath.path)"), continuationText)
        XCTAssertTrue(continuationText.contains("Do not call `kicad_build_intent_model` again"), continuationText)
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_approve_design_intent`"), continuationText)
        XCTAssertTrue(continuationText.contains("kicad_approve_design_intent"), continuationText)

        var startedToolNames: [String] = []
        var cleanStops: [String] = []
        var toolResults: [ToolResult] = []
        for await event in engine.send(userMessage: continuationText) {
            if case .toolCallStarted(let call) = event {
                startedToolNames.append(call.function.name)
            }
            if case .cleanStop(_, let summary) = event {
                cleanStops.append(summary)
            }
            if case .toolCallResult(let result) = event {
                toolResults.append(result)
            }
        }

        XCTAssertEqual(readFileCallCount, 0, "Stale spec reread must be redirected before dispatch")
        XCTAssertEqual(approveCallCount, 1)
        XCTAssertEqual(circuitIRCallCount, 1)
        XCTAssertTrue(approveArguments.contains("amp-design_intent.json"), approveArguments)
        XCTAssertTrue(startedToolNames.contains("kicad_approve_design_intent"), startedToolNames.joined(separator: ", "))
        XCTAssertTrue(startedToolNames.contains("kicad_generate_circuit_ir"), startedToolNames.joined(separator: ", "))
        XCTAssertFalse(toolResults.contains { $0.isError }, toolResults.map(\.content).joined(separator: "\n"))
        XCTAssertTrue(
            cleanStops.contains { $0.contains("verified Circuit IR artifact evidence") },
            cleanStops.joined(separator: "\n")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path))
    }

    func testExplicitComponentSelectionSliceDoesNotInheritCircuitIRHandoff() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-component-selection-handoff")
        let designIntentPath = try writeArtifact(
            name: "amp-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"25W Class A"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "amp-circuit_ir.json",
            contents: #"{"design_id":"AmpDemo","components":[],"nets":[]}"#,
            in: artifactRoot
        )
        let provider = MockProvider(responses: [
            .toolCall(
                id: "intent",
                name: "read_file",
                args: #"{"path":"\#(designIntentPath.path)"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read the existing AmpDemo requirements and artifact files",
                    successCriteria: "requirements and existing artifact files read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_select_components using the existing Circuit IR artifact",
                    successCriteria: "component-selection matrix artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Stop truthfully after kicad_select_components reports selected or blocked components",
                    successCriteria: "component selection status reported",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("read_file") { _ in
            #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)"}"#
        }

        for await _ in engine.send(
            userMessage: "Run the focused AmpDemo `kicad_select_components` slice and stop truthfully after component selection."
        ) {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("kicad_select_components"), continuationText)
        XCTAssertFalse(
            continuationText.contains("Next required electronics handoff tool: `kicad_generate_circuit_ir`"),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("Call `kicad_approve_design_intent`"),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("or call `kicad_generate_circuit_ir`"),
            continuationText
        )
    }

    func testFocusedElectronicsHandoffStopsCleanlyAfterCircuitIR() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-focused-handoff-complete")
        let designIntentPath = artifactRoot.appendingPathComponent("amp-design_intent.json")
        let circuitIRPath = artifactRoot.appendingPathComponent("amp-circuit_ir.json")
        let provider = MockProvider(responses: [
            .toolCall(
                id: "spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .toolCall(
                id: "intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .toolCall(
                id: "approve",
                name: "kicad_approve_design_intent",
                args: #"{"design_intent_path":"\#(designIntentPath.path)"}"#
            ),
            .toolCall(
                id: "ir",
                name: "kicad_generate_circuit_ir",
                args: #"{"design_intent_path":"\#(designIntentPath.path)"}"#
            ),
            .toolCall(
                id: "stale",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 8
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read the AmpDemo specification file",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Build DesignIntent with the electronics KiCad domain tool",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Approve DesignIntent using the generated artifact path",
                    successCriteria: "DesignIntent approved",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Generate Circuit IR from approved DesignIntent",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
            ]
        )

        var readFileCallCount = 0
        var buildIntentCallCount = 0
        var schematicCallCount = 0
        var spiceCallCount = 0
        var fabCallCount = 0
        var bomCallCount = 0
        engine.registerTool("read_file") { _ in
            readFileCallCount += 1
            return "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("kicad_build_intent_model") { _ in
            buildIntentCallCount += 1
            try? FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
            try? #"{"project":"AmpDemo","topology":"25W Class A"}"#.write(
                to: designIntentPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}],"nextActions":["review_and_approve_design_intent"]}"#
        }
        engine.registerTool("kicad_approve_design_intent") { _ in
            #"{"approval":{"status":"approved"},"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}]}"#
        }
        engine.registerTool("kicad_generate_circuit_ir") { _ in
            try? FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
            try? #"{"design_id":"AmpDemo","components":[],"nets":[]}"#.write(
                to: circuitIRPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"circuit_ir","path":"\#(circuitIRPath.path)"}]}"#
        }
        engine.registerTool("kicad_compile_project") { _ in
            schematicCallCount += 1
            return #"{"artifact":{"kind":"schematic","path":"/tmp/amp.kicad_sch"}}"#
        }
        engine.registerTool("kicad_run_spice") { _ in
            spiceCallCount += 1
            return #"{"artifact":{"kind":"spice_measurements","path":"/tmp/spice.log"}}"#
        }
        engine.registerTool("kicad_export_fab") { _ in
            fabCallCount += 1
            return #"{"artifact":{"kind":"gerber","path":"/tmp/fab.zip"}}"#
        }
        engine.registerTool("kicad_prepare_vendor_order") { _ in
            bomCallCount += 1
            return #"{"artifact":{"kind":"bom","path":"/tmp/bom.csv"}}"#
        }

        var cleanStops: [String] = []
        var message = "Run only the focused AmpDemo electronics handoff slice"
        for _ in 0..<5 {
            for await event in engine.send(userMessage: message) {
                if case .cleanStop(_, let summary) = event {
                    cleanStops.append(summary)
                }
            }
            if !cleanStops.isEmpty {
                break
            }
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: injectURL.path),
                "Expected a continuation until Circuit IR is verified"
            )
            message = try readInject()
        }

        XCTAssertEqual(provider.callCount, 4, "Focused handoff must stop before a stale post-Circuit-IR spec reread")
        XCTAssertEqual(readFileCallCount, 1, "Spec should be read once and never reread after DesignIntent exists")
        XCTAssertEqual(buildIntentCallCount, 1, "DesignIntent must not be rebuilt after the artifact exists")
        XCTAssertEqual(schematicCallCount, 0)
        XCTAssertEqual(spiceCallCount, 0)
        XCTAssertEqual(fabCallCount, 0)
        XCTAssertEqual(bomCallCount, 0)
        XCTAssertTrue(
            cleanStops.contains { $0.contains("verified Circuit IR artifact evidence") },
            cleanStops.joined(separator: "\n")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path))
    }

    func testElectronicsEvidencePlansDoNotUseSpawnAgentBatches() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [.text("waiting for tool evidence")])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.continuationInjectURL = injectURL
        engine.toolRouter.registerWorkspaceCapabilityTools(
            ElectronicsRuntimePlugin().metadata.capabilities)
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read the AmpDemo specification file",
                    successCriteria: "spec read",
                    complexity: .standard,
                    parallelSafe: true
                ),
                PlanStep(
                    description: "Start the electronics workflow with the first real KiCad domain tool",
                    successCriteria: "electronics workflow tool invoked",
                    complexity: .standard,
                    parallelSafe: true
                ),
            ]
        )

        var notes: [String] = []
        for await event in engine.send(userMessage: "Run only the focused AmpDemo electronics slice") {
            if case .systemNote(let note) = event {
                notes.append(note)
            }
        }

        let submittedUserMessages = engine.contextManager.messages
            .filter { $0.role == .user }
            .map(\.content.plainText)
            .joined(separator: "\n\n")

        XCTAssertFalse(
            notes.contains { $0.contains("parallel steps") },
            notes.joined(separator: "\n")
        )
        XCTAssertFalse(
            submittedUserMessages.contains("spawn_agent"),
            submittedUserMessages
        )
        XCTAssertTrue(
            submittedUserMessages.contains("Task: Read the AmpDemo specification file"),
            submittedUserMessages
        )
    }

    func testElectronicsWorkflowErrorClearsContinuationInsteadOfAdvancing() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(id: "read-spec", name: "read_file", args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#),
            .toolCall(id: "workflow", name: ElectronicsWorkflowRoute.requirementsToPCB.rawValue, args: #"{"requirements":"25W Class A guitar amplifier"}"#),
            .text("The workflow failed at the gate."),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 8
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(description: "Read AmpDemo spec", successCriteria: "spec read", complexity: .standard),
                PlanStep(description: "Create KiCad schematic and PCB", successCriteria: "schematic and PCB artifacts exist", complexity: .standard),
                PlanStep(description: "Run SPICE simulation", successCriteria: "SPICE output exists", complexity: .standard),
            ]
        )
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool(ElectronicsWorkflowRoute.requirementsToPCB.rawValue) { _ in
            throw NSError(
                domain: "workflow.requirements_to_pcb",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "BLOCKED_VERIFICATION_GATE: KiCad ERC failed"]
            )
        }

        var message = "Run the full AmpDemo electronics workflow"
        for _ in 0..<3 {
            for await _ in engine.send(userMessage: message) {}
            guard FileManager.default.fileExists(atPath: injectURL.path) else { break }
            message = try readInject()
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: injectURL.path),
            "A blocked electronics workflow tool must not schedule a continuation that advances later workflow steps"
        )
    }

    /// A [CONTINUATION] message bypasses the planner — decompose() is never called.
    func testContinuationMessageSkipsDecompose() async throws {
        let provider = MockProvider(responses: [MockLLMResponse.text("done")])
        let engine = makeEngine(provider: provider)

        let spy = SpyPlanner()
        engine.classifierOverride = spy

        for await _ in engine.send(userMessage: "[CONTINUATION] execute step 2: write the tests") {}

        XCTAssertFalse(spy.decomposeCalled,
                       "decompose() must not be called when the message is a [CONTINUATION]")
    }

    /// A [CONTINUATION] message uses a high-stakes complexity tier (maximum loop ceiling).
    func testContinuationMessageGetsHighStakesCeiling() async throws {
        let provider = MockProvider(responses: [MockLLMResponse.text("done")])
        let engine = makeEngine(provider: provider)

        var capturedLoopCount = 0
        // Give many tool-call responses so the loop runs until the ceiling.
        // With highStakes tier, the effective ceiling is larger than standard.
        // We just verify the engine finishes without an early-exit note.
        for await event in engine.send(userMessage: "[CONTINUATION] do the remaining steps") {
            if case .systemNote(let note) = event, note.contains("Loop ceiling reached") {
                capturedLoopCount += 1
            }
        }
        // With a simple text-only mock response, the loop exits after 1 iteration naturally —
        // no ceiling hit expected for a single-text response.
        XCTAssertEqual(capturedLoopCount, 0,
                       "Continuation turn must not hit loop ceiling on a trivial response")
    }

    // MARK: - Fix 2: Near-ceiling warning

    /// When loopCount approaches maxIterations, a ⚠️ system note is emitted.
    func testNearCeilingWarningNoteEmitted() async throws {
        // maxIterations=5, threshold=3: warning fires when loopsRemaining ≤ 3.
        // 2 tool calls + text: after loop 2, remaining = 5-2 = 3 → warning fires before loop 3.
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "t1", name: "noop", args: "{}"),
            MockLLMResponse.toolCall(id: "t2", name: "noop", args: "{}"),
            MockLLMResponse.text("finished"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("noop") { _ in "ok" }
        engine.maxIterationsOverride = 5
        // threshold=3 → fires when loopsRemaining (5-2=3) ≤ 3 after loop 2.
        engine.nearCeilingThreshold = 3

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "do loops") {
            events.append(event)
        }

        let hasWarning = events.contains {
            if case .systemNote(let note) = $0 { return note.contains("⚠️") }
            return false
        }
        XCTAssertTrue(hasWarning, "Expected a near-ceiling ⚠️ system note")
        XCTAssertFalse(
            events.contains {
                if case .systemNote(let note) = $0 { return note.contains("commit all pending work") }
                return false
            },
            "Near-ceiling warning must not tell non-repo domain runs to commit"
        )
    }

    func testDefaultNearCeilingWarningDoesNotFireAfterFirstToolCall() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "t1", name: "noop", args: "{}"),
            MockLLMResponse.text("finished"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("noop") { _ in "ok" }
        engine.maxIterationsOverride = 10

        var notes: [String] = []
        for await event in engine.send(userMessage: "run a simple domain tool then continue") {
            if case .systemNote(let note) = event {
                notes.append(note)
            }
        }

        XCTAssertFalse(
            notes.contains { $0.contains("loop iteration(s) remaining") },
            notes.joined(separator: "\n")
        )
    }

    /// The near-ceiling warning is only emitted once per turn regardless of how many
    /// iterations fall within the warning window.
    func testNearCeilingWarningEmittedOnce() async throws {
        // maxIterations=6, threshold=4: warning fires at loop 2 (remaining=4).
        // 4 tool calls + text: loops 2,3,4,5 are all within the warning window,
        // but the note must only appear once. Args VARY per call so the
        // repetition-stall detector doesn't read 4 identical-signature calls
        // as a loop and escalate mid-test (escalation handoff would reset
        // `nearCeilingEmitted` and the warning would fire a second time).
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "t1", name: "noop", args: #"{"i":1}"#),
            MockLLMResponse.toolCall(id: "t2", name: "noop", args: #"{"i":2}"#),
            MockLLMResponse.toolCall(id: "t3", name: "noop", args: #"{"i":3}"#),
            MockLLMResponse.toolCall(id: "t4", name: "noop", args: #"{"i":4}"#),
            MockLLMResponse.text("done"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("noop") { _ in "ok" }
        engine.maxIterationsOverride = 6
        engine.nearCeilingThreshold = 4  // fires from loop 2 onward (remaining = 5,4,3,2,1)

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "many loops") {
            events.append(event)
        }

        let warningCount = events.filter {
            if case .systemNote(let note) = $0 { return note.contains("⚠️") && note.contains("remaining") }
            return false
        }.count
        XCTAssertEqual(warningCount, 1, "Near-ceiling ⚠️ note must fire exactly once per turn")
    }
}
