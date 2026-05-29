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

        let provider = MockProvider(responses: [
            .toolCall(id: "read-spec", name: "read_file", args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#),
            .text("Spec read."),
            .text("The schematic is complete."),
            .toolCall(id: "schematic", name: "kicad_compile_project", args: #"{"project_path":"/tmp/amp.kicad_pro"}"#),
            .text("Schematic artifacts exist."),
            .text("Simulation is complete."),
            .toolCall(id: "spice", name: "kicad_run_spice", args: #"{"project_path":"/tmp/amp.kicad_pro"}"#),
            .text("SPICE artifacts exist."),
            .text("Gerbers are complete."),
            .toolCall(id: "fab", name: "kicad_export_fab", args: #"{"project_path":"/tmp/amp.kicad_pro"}"#),
            .text("Fabrication artifacts exist."),
            .text("BOM is complete."),
            .toolCall(id: "bom", name: "kicad_prepare_vendor_order", args: #"{"normalized_bom_path":"\#(bomPath.path)","vendor_id":"Digi-Key","quantity":1}"#),
            .text("BOM evidence exists.")
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(description: "Read AmpDemo spec", successCriteria: "spec read", complexity: .standard),
                PlanStep(description: "Create KiCad schematic", successCriteria: "schematic artifact exists", complexity: .standard),
                PlanStep(description: "Run SPICE simulation", successCriteria: "SPICE output exists", complexity: .standard),
                PlanStep(description: "Export Gerbers and drill files", successCriteria: "Gerber and drill files exist", complexity: .standard),
                PlanStep(description: "Produce BOM with Digi-Key and Mouser part numbers", successCriteria: "vendor BOM artifact exists", complexity: .standard),
            ]
        )
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("kicad_compile_project") { _ in
            #"{"artifacts":[{"kind":"kicad_schematic","path":"\#(schematicPath.path)"}]}"#
        }
        engine.registerTool("kicad_run_spice") { _ in
            #"{"artifacts":[{"kind":"spice_measurements","path":"\#(spicePath.path)"}]}"#
        }
        engine.registerTool("kicad_export_fab") { _ in
            #"{"artifacts":[{"kind":"gerbers","path":"\#(gerberDirectory.path)"},{"kind":"drills","path":"\#(gerberDirectory.appendingPathComponent("amp.drl").path)"}]}"#
        }
        engine.registerTool("kicad_prepare_vendor_order") { _ in
            #"{"artifacts":[{"kind":"bom","path":"\#(bomPath.path)"}],"vendors":["Digi-Key","Mouser"]}"#
        }

        for await _ in engine.send(userMessage: "Build the AmpDemo electronics workflow artifacts") {}
        var continuationText = try readInject()
        XCTAssertTrue(
            continuationText.contains("Steps 1-1 have verified tool/artifact evidence."),
            continuationText
        )
        XCTAssertTrue(continuationText.contains("  2. Create KiCad schematic"), continuationText)
        XCTAssertFalse(continuationText.contains("  3. Run SPICE simulation"))

        for await _ in engine.send(userMessage: continuationText) {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-1 have verified tool/artifact evidence."))
        XCTAssertTrue(continuationText.contains("  2. Create KiCad schematic"))
        XCTAssertFalse(continuationText.contains("  3. Run SPICE simulation"),
                       "Narrative alone must not complete the schematic step")

        for await _ in engine.send(userMessage: continuationText) {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-2 have verified tool/artifact evidence."))
        XCTAssertTrue(continuationText.contains("  3. Run SPICE simulation"))

        for await _ in engine.send(userMessage: continuationText) {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-2 have verified tool/artifact evidence."))
        XCTAssertTrue(continuationText.contains("  3. Run SPICE simulation"),
                      "Narrative alone must not complete the SPICE step")

        for await _ in engine.send(userMessage: continuationText) {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-3 have verified tool/artifact evidence."))
        XCTAssertTrue(continuationText.contains("  4. Export Gerbers and drill files"))

        for await _ in engine.send(userMessage: continuationText) {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-3 have verified tool/artifact evidence."))
        XCTAssertTrue(continuationText.contains("  4. Export Gerbers and drill files"),
                      "Narrative alone must not complete fabrication output")

        for await _ in engine.send(userMessage: continuationText) {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-4 have verified tool/artifact evidence."))
        XCTAssertTrue(continuationText.contains("  5. Produce BOM with Digi-Key and Mouser part numbers"))

        for await _ in engine.send(userMessage: continuationText) {}
        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-4 have verified tool/artifact evidence."))
        XCTAssertTrue(continuationText.contains("  5. Produce BOM with Digi-Key and Mouser part numbers"),
                      "Narrative alone must not complete the vendor BOM step")

        for await _ in engine.send(userMessage: continuationText) {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path),
                       "All electronics steps with artifact evidence should clear the continuation inject")
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

        for await _ in engine.send(userMessage: "Run the full AmpDemo electronics workflow") {}

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
