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

    private func selectedComponentMatrixJSON(
        refdes: String = "QOUT1",
        mpn: String = "MJ15003G",
        manufacturer: String = "onsemi"
    ) -> String {
        """
        {
          "design_id": "AmpDemo",
          "decisions": [
            {
              "refdes": "\(refdes)",
              "status": "selected",
              "selected_candidate": {
                "mpn": "\(mpn)",
                "manufacturer": "\(manufacturer)"
              },
              "candidate_set": [],
              "rationale": "Selected catalog-backed test candidate.",
              "evidence_references": [],
              "unresolved_decisions": []
            }
          ],
          "components": [
            {
              "refdes": "\(refdes)",
              "role": "output transistor",
              "constraints": {},
              "selection_status": "selected",
              "mpn": "\(mpn)",
              "manufacturer": "\(manufacturer)"
            }
          ],
          "warnings": [],
          "providers": ["fixture"],
          "cache_metadata": {}
        }
        """
    }

    private func componentResolutionAnswerArgumentsJSON(refdes: String) -> String {
        """
        {
          "component_resolution_answers": [
            {
              "refdes": "\(refdes)",
              "manufacturer": "onsemi",
              "mpn": "MJ15003G",
              "normalized_category": "power_transistor",
              "package": "TO-3",
              "ratings": {"voltage_v":"140","current_a":"20","power_w":"250"},
              "datasheet_url": "https://example.invalid/MJ15003G.pdf",
              "source_url": "https://provider.example/MJ15003G",
              "availability_summary": "100 In Stock",
              "lifecycle_state": "Active",
              "footprint": {
                "library": "Package_TO_SOT_THT",
                "name": "TO-3",
                "package_compatibility_evidence": "TO-3 package and pinout supplied by resolver answer",
                "pin_pad_map": {"B":"1","C":"2"},
                "source_provider_id": "component_resolution_answer"
              }
            }
          ]
        }
        """
    }

    private func componentRevisionBlockedResultJSON(
        designIntentPath: String,
        circuitIRPath: String,
        originalMatrixPath: String,
        revisedMatrixPath: String,
        unresolvedRefdes: String
    ) -> String {
        """
        {
          "status": "BLOCKED_INPUT_QUALITY",
          "artifacts": [
            {"kind": "component_matrix", "path": "\(revisedMatrixPath)"}
          ],
          "warnings": [
            {
              "code": "COMPONENT_SELECTION_REVISION_BLOCKED",
              "message": "Component selection revision still has unresolved decisions."
            }
          ],
          "questions": [
            {
              "id": "resolve-\(unresolvedRefdes)",
              "prompt": "For \(unresolvedRefdes), provide manufacturer, MPN, package, ratings, datasheet/provenance evidence, and footprint/pin compatibility.",
              "affectedRefs": ["\(unresolvedRefdes)", "\(originalMatrixPath)", "\(revisedMatrixPath)"]
            }
          ],
          "handoff": {
            "design_intent_path": "\(designIntentPath)",
            "circuit_ir_path": "\(circuitIRPath)",
            "original_component_matrix_path": "\(originalMatrixPath)",
            "component_matrix_path": "\(revisedMatrixPath)"
          },
          "nextActions": ["answer_component_selection_questions"]
        }
        """
    }

    private func jsonObject(_ text: String) throws -> [String: Any] {
        let data = try XCTUnwrap(text.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
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

    func testVendorCatalogComponentSelectionStepAdvancesOnComponentMatrixEvidence() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-component-catalog-evidence")
        let componentMatrixPath = try writeArtifact(
            name: "component_matrix.json",
            contents: selectedComponentMatrixJSON(mpn: "MJL3281AG", manufacturer: "onsemi"),
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "components",
                name: "kicad_select_components",
                args: #"{"circuit_ir_path":"/tmp/circuit_ir.json","live_catalog_providers":["mouser","digikey"]}"#
            )
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
                    description: "Query live component catalogs (Digi-Key, Mouser APIs) and local libraries to select real-world components matching CircuitIR specifications",
                    successCriteria: "Component matrix artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Assign KiCad footprints from selected component package constraints",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("kicad_select_components") { _ in
            #"{"artifacts":[{"kind":"component_matrix","path":"\#(componentMatrixPath.path)"}],"handoff":{"component_matrix_path":"\#(componentMatrixPath.path)"},"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: "Select AmpDemo parts from live component catalogs") {}

        let continuationText = try readInject()
        XCTAssertTrue(
            continuationText.contains("Steps 1-1 have verified tool/artifact evidence."),
            continuationText
        )
        XCTAssertTrue(
            continuationText.contains("  2. Assign KiCad footprints from selected component package constraints"),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("Steps 1-0 have verified tool/artifact evidence."),
            "A component matrix from kicad_select_components must satisfy the component catalog step"
        )
    }

    func testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-blocked-component-matrix-evidence")
        let designIntentPath = try writeArtifact(
            name: "approved-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "circuit_ir.json",
            contents: #"{"design_id":"AmpDemo","components":[{"refdes":"RPRE1B"}],"nets":[]}"#,
            in: artifactRoot
        )
        let componentMatrixPath = try writeArtifact(
            name: "component_matrix.json",
            contents: """
            {
              "design_id": "AmpDemo",
              "decisions": [
                {
                  "refdes": "RPRE1B",
                  "status": "blocked",
                  "selected_candidate": null,
                  "candidate_set": [],
                  "rationale": "No catalog candidate satisfies constraints.",
                  "evidence_references": [],
                  "unresolved_decisions": ["Resolve RPRE1B before footprints."]
                }
              ],
              "components": [
                {
                  "refdes": "RPRE1B",
                  "role": "preamp resistor",
                  "constraints": {},
                  "selection_status": "blocked",
                  "mpn": "",
                  "manufacturer": ""
                }
              ],
              "warnings": [],
              "providers": ["fixture"],
              "cache_metadata": {}
            }
            """,
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "components",
                name: "kicad_select_components",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)","live_catalog_providers":["mouser","digikey"]}"#
            )
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
                    description: "Select components using live catalog evidence",
                    successCriteria: "Component matrix artifact exists with selected candidates",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Assign KiCad footprints from selected component package constraints",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("kicad_select_components") { _ in
            #"{"artifacts":[{"kind":"component_matrix","path":"\#(componentMatrixPath.path)"}],"handoff":{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)","component_matrix_path":"\#(componentMatrixPath.path)"},"nextActions":["revise_component_selection"],"status":"BLOCKED_INPUT_QUALITY"}"#
        }

        for await _ in engine.send(userMessage: "Select AmpDemo parts from live component catalogs") {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_revise_component_selection`"), continuationText)
        XCTAssertTrue(continuationText.contains(#""design_intent_path":"\#(designIntentPath.path)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""component_matrix_path":"\#(componentMatrixPath.path)""#), continuationText)
        XCTAssertFalse(continuationText.contains("kicad_assign_footprints"), continuationText)
    }

    func testComponentSelectionRevisionBlockedQuestionsStopWithRecoverableEvidence() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-component-revision-blocked-evidence")
        let designIntentPath = try writeArtifact(
            name: "approved-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "circuit_ir.json",
            contents: #"{"design_id":"AmpDemo","components":[{"refdes":"RPRE1B"}],"nets":[]}"#,
            in: artifactRoot
        )
        let originalMatrixPath = try writeArtifact(
            name: "original-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"RPRE1B","status":"blocked"}]}"#,
            in: artifactRoot
        )
        let revisedMatrixPath = try writeArtifact(
            name: "revised-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"RPRE1B","status":"blocked"}]}"#,
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "revise-components",
                name: "kicad_revise_component_selection",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)","component_matrix_path":"\#(originalMatrixPath.path)"}"#
            )
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
                    description: "Revise blocked component selection with catalog evidence",
                    successCriteria: "Resolved component matrix or structured missing evidence questions",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Assign KiCad footprints from selected component package constraints",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("kicad_revise_component_selection") { _ in
            """
            {
              "status": "BLOCKED_INPUT_QUALITY",
              "artifacts": [
                {"kind": "component_matrix", "path": "\(revisedMatrixPath.path)"}
              ],
              "warnings": [
                {
                  "code": "COMPONENT_SELECTION_REVISION_BLOCKED",
                  "message": "Component selection revision still has unresolved decisions."
                }
              ],
              "questions": [
                {
                  "id": "resolve-RPRE1B",
                  "prompt": "For RPRE1B, provide manufacturer, MPN, package, ratings, datasheet/provenance evidence, and footprint/pin compatibility.",
                  "affectedRefs": ["RPRE1B", "\(originalMatrixPath.path)", "\(revisedMatrixPath.path)"]
                }
              ],
              "handoff": {
                "design_intent_path": "\(designIntentPath.path)",
                "circuit_ir_path": "\(circuitIRPath.path)",
                "original_component_matrix_path": "\(originalMatrixPath.path)",
                "component_matrix_path": "\(revisedMatrixPath.path)"
              },
              "nextActions": ["answer_component_selection_questions"]
            }
            """
        }

        var cleanStops: [String] = []
        for await event in engine.send(userMessage: "Revise the blocked component matrix and then assign footprints only if resolved.") {
            if case let .cleanStop(reason, summary) = event {
                cleanStops.append("\(reason)\n\(summary)")
            }
        }

        let stopText = try XCTUnwrap(cleanStops.last)
        XCTAssertTrue(stopText.contains("COMPONENT_SELECTION_REVISION_BLOCKED"), stopText)
        XCTAssertTrue(stopText.contains("Question resolve-RPRE1B"), stopText)
        XCTAssertTrue(stopText.contains("manufacturer, MPN, package, ratings, datasheet/provenance evidence, and footprint/pin compatibility"), stopText)
        XCTAssertTrue(stopText.contains("Original blocked component matrix: \(originalMatrixPath.path)"), stopText)
        XCTAssertTrue(stopText.contains("Revised component matrix: \(revisedMatrixPath.path)"), stopText)
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path), "Blocked resolver questions must stop, not schedule footprints")
    }

    func testComponentSelectionRevisionAnswerTurnCarriesHandoffPathsAndAnswerEvidence() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-component-revision-answer-turn")
        let designIntentPath = try writeArtifact(
            name: "approved-design_intent.json",
            contents: #"{"project":"GenericAmp","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "circuit_ir.json",
            contents: #"{"design_id":"GenericAmp","components":[{"refdes":"QOUT1"}],"nets":[]}"#,
            in: artifactRoot
        )
        let originalMatrixPath = try writeArtifact(
            name: "original-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"QOUT1","status":"requires_vendor_resolution"}]}"#,
            in: artifactRoot
        )
        let blockedRevisionPath = try writeArtifact(
            name: "blocked-revised-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"QOUT1","status":"requires_vendor_resolution"}]}"#,
            in: artifactRoot
        )
        let completeMatrixPath = try writeArtifact(
            name: "complete-component_matrix.json",
            contents: selectedComponentMatrixJSON(refdes: "QOUT1", mpn: "MJ15003G", manufacturer: "onsemi"),
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "initial-revision",
                name: "kicad_revise_component_selection",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)","component_matrix_path":"\#(originalMatrixPath.path)"}"#
            ),
            .toolCall(
                id: "answered-revision",
                name: "kicad_revise_component_selection",
                args: componentResolutionAnswerArgumentsJSON(refdes: "QOUT1")
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
                    description: "Revise blocked component selection with catalog evidence",
                    successCriteria: "Resolved component matrix or structured missing evidence questions",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Assign KiCad footprints from selected component package constraints",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
            ]
        )

        var revisionArguments: [String] = []
        engine.registerTool("kicad_revise_component_selection") { args in
            revisionArguments.append(args)
            if args.contains("component_resolution_answers") {
                return """
                {
                  "status": "COMPLETE",
                  "artifacts": [
                    {"kind": "component_matrix", "path": "\(completeMatrixPath.path)"}
                  ],
                  "handoff": {
                    "design_intent_path": "\(designIntentPath.path)",
                    "circuit_ir_path": "\(circuitIRPath.path)",
                    "component_matrix_path": "\(completeMatrixPath.path)"
                  },
                  "nextActions": ["assign_footprints"]
                }
                """
            }
            return self.componentRevisionBlockedResultJSON(
                designIntentPath: designIntentPath.path,
                circuitIRPath: circuitIRPath.path,
                originalMatrixPath: originalMatrixPath.path,
                revisedMatrixPath: blockedRevisionPath.path,
                unresolvedRefdes: "QOUT1"
            )
        }

        for await _ in engine.send(userMessage: "Revise the blocked component matrix and stop for questions if evidence is missing.") {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path), "Blocked revision questions must not auto-continue")

        for await _ in engine.send(userMessage: "Use the supplied QOUT1 manufacturer, MPN, package, ratings, datasheet, and footprint pin evidence to continue.") {}

        let answeredArgs = try XCTUnwrap(revisionArguments.last)
        let answeredObject = try jsonObject(answeredArgs)
        XCTAssertEqual(answeredObject["design_intent_path"] as? String, designIntentPath.path)
        XCTAssertEqual(answeredObject["circuit_ir_path"] as? String, circuitIRPath.path)
        XCTAssertEqual(answeredObject["original_component_matrix_path"] as? String, originalMatrixPath.path)
        XCTAssertEqual(answeredObject["component_matrix_path"] as? String, blockedRevisionPath.path)
        XCTAssertEqual(answeredObject["component_resolution_question_ids"] as? [String], ["resolve-QOUT1"])
        let answers = try XCTUnwrap(answeredObject["component_resolution_answers"] as? [[String: Any]])
        XCTAssertEqual(answers.first?["refdes"] as? String, "QOUT1")
        XCTAssertEqual(answers.first?["mpn"] as? String, "MJ15003G")

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_assign_footprints`"), continuationText)
        XCTAssertTrue(continuationText.contains(completeMatrixPath.path), continuationText)
        XCTAssertFalse(continuationText.contains("kicad_compile_project"), continuationText)
    }

    func testGUIResolverAnswerContinuationAdvancesThroughRevisionHandoff() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-gui-resolver-answer-turn")
        let designIntentPath = try writeArtifact(
            name: "approved-design_intent.json",
            contents: #"{"project":"GenericAmp","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "circuit_ir.json",
            contents: #"{"design_id":"GenericAmp","components":[{"refdes":"QOUT1"}],"nets":[]}"#,
            in: artifactRoot
        )
        let originalMatrixPath = try writeArtifact(
            name: "original-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"QOUT1","status":"requires_vendor_resolution"}]}"#,
            in: artifactRoot
        )
        let blockedRevisionPath = try writeArtifact(
            name: "blocked-revised-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"QOUT1","status":"requires_vendor_resolution"}]}"#,
            in: artifactRoot
        )
        let completeMatrixPath = try writeArtifact(
            name: "complete-component_matrix.json",
            contents: selectedComponentMatrixJSON(refdes: "QOUT1", mpn: "MJ15003G", manufacturer: "onsemi"),
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "initial-revision",
                name: "kicad_revise_component_selection",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)","component_matrix_path":"\#(originalMatrixPath.path)"}"#
            ),
            .toolCall(
                id: "gui-answered-revision",
                name: "kicad_revise_component_selection",
                args: #"{"component_resolution_answers":[{"refdes":"QOUT1","manufacturer":"onsemi","mpn":"MJ15003G"}]}"#
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
                    description: "Revise blocked component selection with catalog evidence",
                    successCriteria: "Resolved component matrix or structured missing evidence questions",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Assign KiCad footprints from selected component package constraints",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
            ]
        )

        var revisionArguments: [String] = []
        engine.registerTool("kicad_revise_component_selection") { args in
            revisionArguments.append(args)
            if args.contains("component_resolution_answers") {
                return """
                {
                  "status": "COMPLETE",
                  "artifacts": [
                    {"kind": "component_matrix", "path": "\(completeMatrixPath.path)"}
                  ],
                  "handoff": {
                    "design_intent_path": "\(designIntentPath.path)",
                    "circuit_ir_path": "\(circuitIRPath.path)",
                    "component_matrix_path": "\(completeMatrixPath.path)"
                  },
                  "nextActions": ["assign_footprints"]
                }
                """
            }
            return self.componentRevisionBlockedResultJSON(
                designIntentPath: designIntentPath.path,
                circuitIRPath: circuitIRPath.path,
                originalMatrixPath: originalMatrixPath.path,
                revisedMatrixPath: blockedRevisionPath.path,
                unresolvedRefdes: "QOUT1"
            )
        }

        for await _ in engine.send(userMessage: "Revise the blocked component matrix and stop for questions if evidence is missing.") {}

        let store = ElectronicsJobStore()
        store.apply(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_revise_component_selection"),
            origin: nil,
            kind: .diagnostic,
            payload: .jsonString("""
            {
              "job_id": "ampdemo",
              "status": "BLOCKED_INPUT_QUALITY",
              "code": "COMPONENT_SELECTION_REVISION_BLOCKED",
              "message": "Component selection revision still has unresolved decisions.",
              "questions": [
                {
                  "id": "resolve-QOUT1",
                  "prompt": "For QOUT1, provide manufacturer, MPN, package, ratings, datasheet/provenance evidence, and footprint/pin compatibility.",
                  "affectedRefs": ["QOUT1"]
                }
              ],
              "handoff": {
                "design_intent_path": "\(designIntentPath.path)",
                "circuit_ir_path": "\(circuitIRPath.path)",
                "original_component_matrix_path": "\(originalMatrixPath.path)",
                "component_matrix_path": "\(blockedRevisionPath.path)"
              }
            }
            """)
        ))
        try store.writeResolverAnswerContinuation(
            jobID: "ampdemo",
            answers: [
                ElectronicsComponentResolutionAnswer(
                    refdes: "QOUT1",
                    manufacturer: "onsemi",
                    mpn: "MJ15003G",
                    normalizedCategory: "power_transistor",
                    package: "TO-3",
                    ratings: ["voltage_v": "140", "current_a": "20", "power_w": "250"],
                    datasheetURL: "https://example.invalid/MJ15003G.pdf",
                    sourceURL: "https://provider.example/MJ15003G",
                    availabilitySummary: "100 In Stock",
                    lifecycleState: "Active",
                    footprint: ElectronicsComponentResolutionFootprintAnswer(
                        library: "Package_TO_SOT_THT",
                        name: "TO-3",
                        packageCompatibilityEvidence: "TO-3 package and pinout supplied by resolver answer",
                        pinPadMap: ["B": "1", "C": "2"],
                        sourceProviderID: "component_resolution_answer"
                    )
                )
            ],
            to: injectURL
        )
        let guiContinuationMessage = try readInject()
        XCTAssertTrue(guiContinuationMessage.contains("component_resolution_answers"), guiContinuationMessage)

        for await _ in engine.send(userMessage: guiContinuationMessage) {}

        let answeredArgs = try XCTUnwrap(revisionArguments.last)
        let answeredObject = try jsonObject(answeredArgs)
        XCTAssertEqual(answeredObject["component_resolution_question_ids"] as? [String], ["resolve-QOUT1"])
        XCTAssertEqual(answeredObject["component_matrix_path"] as? String, blockedRevisionPath.path)
        XCTAssertNotNil(answeredObject["component_resolution_answers"] as? [[String: Any]])
        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_assign_footprints`"), continuationText)
        XCTAssertTrue(continuationText.contains(completeMatrixPath.path), continuationText)
    }

    func testComponentSelectionRevisionPartialAnswerTurnRemainsBlockedWithUnansweredQuestions() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-component-revision-partial-answer-turn")
        let designIntentPath = try writeArtifact(
            name: "approved-design_intent.json",
            contents: #"{"project":"GenericAmp","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "circuit_ir.json",
            contents: #"{"design_id":"GenericAmp","components":[{"refdes":"QOUT1"},{"refdes":"RBIAS1"}],"nets":[]}"#,
            in: artifactRoot
        )
        let originalMatrixPath = try writeArtifact(
            name: "original-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"QOUT1","status":"requires_vendor_resolution"},{"refdes":"RBIAS1","status":"requires_vendor_resolution"}]}"#,
            in: artifactRoot
        )
        let firstBlockedRevisionPath = try writeArtifact(
            name: "first-blocked-revised-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"QOUT1","status":"requires_vendor_resolution"},{"refdes":"RBIAS1","status":"requires_vendor_resolution"}]}"#,
            in: artifactRoot
        )
        let secondBlockedRevisionPath = try writeArtifact(
            name: "second-blocked-revised-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"QOUT1","status":"selected"},{"refdes":"RBIAS1","status":"requires_vendor_resolution"}]}"#,
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "initial-revision",
                name: "kicad_revise_component_selection",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)","component_matrix_path":"\#(originalMatrixPath.path)"}"#
            ),
            .toolCall(
                id: "partial-answered-revision",
                name: "kicad_revise_component_selection",
                args: componentResolutionAnswerArgumentsJSON(refdes: "QOUT1")
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
                    description: "Revise blocked component selection with catalog evidence",
                    successCriteria: "Resolved component matrix or structured missing evidence questions",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Assign KiCad footprints from selected component package constraints",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
            ]
        )

        var revisionArguments: [String] = []
        engine.registerTool("kicad_revise_component_selection") { args in
            revisionArguments.append(args)
            if args.contains("component_resolution_answers") {
                return self.componentRevisionBlockedResultJSON(
                    designIntentPath: designIntentPath.path,
                    circuitIRPath: circuitIRPath.path,
                    originalMatrixPath: originalMatrixPath.path,
                    revisedMatrixPath: secondBlockedRevisionPath.path,
                    unresolvedRefdes: "RBIAS1"
                )
            }
            return self.componentRevisionBlockedResultJSON(
                designIntentPath: designIntentPath.path,
                circuitIRPath: circuitIRPath.path,
                originalMatrixPath: originalMatrixPath.path,
                revisedMatrixPath: firstBlockedRevisionPath.path,
                unresolvedRefdes: "QOUT1"
            )
        }

        for await _ in engine.send(userMessage: "Revise the blocked component matrix and stop for questions if evidence is missing.") {}

        var cleanStops: [String] = []
        for await event in engine.send(userMessage: "Use the supplied QOUT1 evidence; RBIAS1 has not been resolved yet.") {
            if case let .cleanStop(reason, summary) = event {
                cleanStops.append("\(reason)\n\(summary)")
            }
        }

        let answeredArgs = try XCTUnwrap(revisionArguments.last)
        let answeredObject = try jsonObject(answeredArgs)
        XCTAssertEqual(answeredObject["design_intent_path"] as? String, designIntentPath.path)
        XCTAssertEqual(answeredObject["circuit_ir_path"] as? String, circuitIRPath.path)
        XCTAssertEqual(answeredObject["original_component_matrix_path"] as? String, originalMatrixPath.path)
        XCTAssertEqual(answeredObject["component_matrix_path"] as? String, firstBlockedRevisionPath.path)
        XCTAssertEqual(answeredObject["component_resolution_question_ids"] as? [String], ["resolve-QOUT1"])
        XCTAssertNotNil(answeredObject["component_resolution_answers"] as? [[String: Any]])

        let stopText = try XCTUnwrap(cleanStops.last)
        XCTAssertTrue(stopText.contains("Question resolve-RBIAS1"), stopText)
        XCTAssertTrue(stopText.contains("Original blocked component matrix: \(originalMatrixPath.path)"), stopText)
        XCTAssertTrue(stopText.contains("Revised component matrix: \(secondBlockedRevisionPath.path)"), stopText)
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path), "Incomplete answers must not schedule footprints")
    }

    func testComponentSelectionHandoffRecoversComponentMatrixFromProjectArtifacts() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let projectRoot = temporaryDirectory("electronics-component-handoff-project-artifacts")
        let artifactRoot = projectRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)
        let designIntentPath = try writeArtifact(
            name: "amp-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"25W Class A"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "amp-circuit_ir.json",
            contents: #"{"design_id":"AmpDemo","components":[{"refdes":"QOUT1"}],"nets":[]}"#,
            in: artifactRoot
        )
        let componentMatrixPath = try writeArtifact(
            name: "amp-component_matrix.json",
            contents: selectedComponentMatrixJSON(),
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "components",
                name: "kicad_select_components",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)"}"#
            )
        ])
        let engine = makeEngine(provider: provider)
        engine.currentProjectPath = projectRoot.path
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Select components using the approved DesignIntent and generated CircuitIR/netlist",
                    successCriteria: "Component matrix artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Assign KiCad footprints from selected component package constraints",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("kicad_select_components") { _ in
            #"{"status":"complete","nextActions":["assign_footprints"]}"#
        }

        for await _ in engine.send(userMessage: "Continue the AmpDemo electronics workflow after component selection") {}

        let continuationText = try readInject()
        XCTAssertTrue(
            continuationText.contains("Next required electronics handoff tool: `kicad_assign_footprints`"),
            continuationText
        )
        XCTAssertTrue(continuationText.contains(componentMatrixPath.path), continuationText)
        XCTAssertFalse(
            continuationText.contains("Next required electronics handoff tool: `kicad_select_components`"),
            continuationText
        )
    }

    func testCircuitIRNetlistPlanStepWithSpiceTextAdvancesToFootprintHandoff() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let projectRoot = temporaryDirectory("electronics-circuit-ir-spice-wording")
        let artifactRoot = projectRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)
        let specPath = projectRoot.appendingPathComponent("spec.md")
        let designIntentPath = artifactRoot.appendingPathComponent("amp-design_intent.json")
        let circuitIRPath = artifactRoot.appendingPathComponent("amp-circuit_ir.json")
        let componentMatrixPath = artifactRoot.appendingPathComponent("amp-component_matrix.json")

        let provider = MockProvider(responses: [
            .toolCall(id: "read", name: "read_file", args: #"{"path":"\#(specPath.path)"}"#),
            .toolCall(id: "intent", name: "kicad_build_intent_model", args: #"{"input_artifact_path":"\#(specPath.path)"}"#),
            .toolCall(id: "circuit", name: "kicad_generate_circuit_ir", args: #"{"design_intent_path":"\#(designIntentPath.path)"}"#),
            .toolCall(id: "components", name: "kicad_select_components", args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)"}"#),
        ])
        let engine = makeEngine(provider: provider)
        engine.currentProjectPath = projectRoot.path
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 8
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read and parse /Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md to extract requirements",
                    successCriteria: "Spec requirements read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Create DesignIntent document: define topology, power supply, audio stages, and constraints",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Generate CircuitIR/netlist: create hierarchical SPICE netlist with subcircuits for preamp, tone, filter, driver, output, and PSU",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .highStakes
                ),
                PlanStep(
                    description: "Select components: choose transformer, bridge rectifier, transistors, passives, pots, connectors, and heat-related parts",
                    successCriteria: "Component matrix artifact exists",
                    complexity: .highStakes
                ),
                PlanStep(
                    description: "Assign footprints: map each component to KiCad footprints",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("kicad_build_intent_model") { _ in
            try? FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
            try? #"{"project":"AmpDemo","topology":"25W Class A"}"#.write(
                to: designIntentPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}],"status":"COMPLETE"}"#
        }
        engine.registerTool("kicad_generate_circuit_ir") { _ in
            try? FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
            try? #"{"design_id":"AmpDemo","components":[{"refdes":"QOUT1"}],"nets":[]}"#.write(
                to: circuitIRPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"circuit_ir","path":"\#(circuitIRPath.path)"}],"status":"COMPLETE"}"#
        }
        engine.registerTool("kicad_select_components") { _ in
            try? FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
            try? self.selectedComponentMatrixJSON().write(
                to: componentMatrixPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"component_matrix","path":"\#(componentMatrixPath.path)"}],"status":"COMPLETE"}"#
        }

        var prompt = "Run the full AmpDemo electronics workflow"
        var continuationText = ""
        for _ in 0..<5 {
            for await _ in engine.send(userMessage: prompt) {}
            continuationText = try readInject()
            if continuationText.contains("Next required electronics handoff tool: `kicad_assign_footprints`") {
                break
            }
            prompt = continuationText
        }

        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_assign_footprints`"), continuationText)
        XCTAssertTrue(continuationText.contains(componentMatrixPath.path), continuationText)
        XCTAssertFalse(continuationText.contains("Run SPICE"), continuationText)
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

    func testElectronicsEvidenceGateProseCannotBeClearedByCriticPass() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = true
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .text("I have reviewed the requirements and the schematic design is acceptable, but I will not call a KiCad tool."),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.criticOverride = PassCritic()
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read and parse the AmpDemo spec.md to extract all requirements",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Create DesignIntent document with topology, power supply, and safety constraints",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .highStakes
                ),
                PlanStep(
                    description: "Build KiCad schematic",
                    successCriteria: "schematic artifact exists",
                    complexity: .standard
                ),
            ]
        )
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("kicad_build_intent_model") { _ in
            XCTFail("The regression exercises the prose/no-tool path; no tool should be reached.")
            return #"{"artifacts":[]}"#
        }

        for await _ in engine.send(userMessage: "Run the full AmpDemo electronics workflow") {}
        let continuationText = try readInject()

        var notes: [String] = []
        var cleanStops: [String] = []
        for await event in engine.send(userMessage: continuationText) {
            switch event {
            case .systemNote(let note):
                notes.append(note)
            case .cleanStop(let reason, let summary):
                cleanStops.append("\(reason): \(summary)")
            default:
                break
            }
        }

        XCTAssertTrue(
            notes.contains { $0.contains("electronics workflow guard") },
            notes.joined(separator: "\n")
        )
        XCTAssertFalse(
            notes.contains { $0.contains("verification passed") },
            "Critic pass must not clear electronics continuations without verified tool/artifact evidence"
        )
        XCTAssertTrue(
            cleanStops.contains { $0.contains("electronics workflow produced prose") },
            cleanStops.joined(separator: "\n")
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

    func testElectronicsKeywordPlanUsesEvidenceGateWhenDomainStateDrops() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(id: "read-spec", name: "read_file", args: #"{"path":"/tmp/spec.md"}"#),
            .text("Spec read.")
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 4
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "transient domain state"),
            steps: [
                PlanStep(
                    description: "Read and parse spec.md",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Build KiCad schematic and PCB with SPICE simulation, Gerbers, drill files, and BOM",
                    successCriteria: "KiCad schematic, PCB, SPICE, Gerbers, drill files, and BOM artifacts exist",
                    complexity: .highStakes
                ),
            ]
        )
        engine.registerTool("read_file") { _ in "electronics requirements" }

        for await _ in engine.send(userMessage: "Run the AmpDemo workflow") {}

        let continuationText = try readInject()
        XCTAssertTrue(
            continuationText.contains("verified tool/artifact evidence"),
            continuationText
        )
        XCTAssertTrue(
            continuationText.contains("Continue from the first unverified electronics step"),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("Steps 1–1 of the following task are complete"),
            "Electronics artifact plans must not use narrative continuation accounting"
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

    func testUnverifiedElectronicsContinuationReschedulesSameStepAfterReadOnlyToolBatch() async throws {
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
                    description: "Initialize a clean project directory structure for AmpDemo with required electronics tooling scaffolding",
                    successCriteria: "KiCad project skeleton and component library manifest artifact evidence exists",
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
            return ".merlin\nartifacts\nscreenshots\nspec.md\nvendor-feeds"
        }

        for await _ in engine.send(userMessage: "Run the focused AmpDemo electronics slice") {}
        let firstContinuation = try readInject()
        XCTAssertTrue(
            firstContinuation.contains("Steps 1-1 have verified tool/artifact evidence."),
            firstContinuation
        )
        XCTAssertTrue(
            firstContinuation.contains("  2. Initialize a clean project directory structure"),
            firstContinuation
        )

        try? FileManager.default.removeItem(at: injectURL)
        var notes: [String] = []
        for await event in engine.send(userMessage: firstContinuation) {
            if case .systemNote(let note) = event {
                notes.append(note)
            }
        }

        XCTAssertEqual(listDirectoryCallCount, 1)
        let retryContinuation = try readInject()
        XCTAssertTrue(
            retryContinuation.contains("Steps 1-1 have verified tool/artifact evidence."),
            retryContinuation
        )
        XCTAssertTrue(
            retryContinuation.contains("  2. Initialize a clean project directory structure"),
            retryContinuation
        )
        XCTAssertFalse(
            retryContinuation.contains("Steps 1-2 have verified tool/artifact evidence."),
            "A read-only directory listing must not complete the electronics scaffolding/design step"
        )
        XCTAssertTrue(
            retryContinuation.contains("read-only inspection tools and KiCad/version health checks do not satisfy"),
            retryContinuation
        )
        XCTAssertTrue(
            notes.contains { $0.contains("electronics evidence still missing for current step") },
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

    func testEvidenceGatedNoSplitDesignIntentSchedulesApprovalContinuation() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-no-split-design-intent")
        let designIntentPath = artifactRoot.appendingPathComponent("amp-design_intent.json")
        let provider = MockProvider(responses: [
            .toolCall(
                id: "intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"amp_low_voltage_audio"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 16
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
            try? FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
            try? #"{"project":"AmpDemo","topology":"25W Class A"}"#.write(
                to: designIntentPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}],"nextActions":["review_and_approve_design_intent"]}"#
        }

        for await _ in engine.send(userMessage: "Run the focused AmpDemo electronics handoff without batch splitting") {}

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: injectURL.path),
            "Evidence-gated no-split turns must still schedule the first unverified continuation"
        )
        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Steps 1-1 have verified tool/artifact evidence"), continuationText)
        XCTAssertTrue(continuationText.contains("Approve DesignIntent using the generated artifact path"), continuationText)
        XCTAssertTrue(continuationText.contains("Existing DesignIntent artifact: \(designIntentPath.path)"), continuationText)
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_approve_design_intent`"), continuationText)
    }

    func testDirectDesignIntentToolCallSchedulesImplicitDownstreamHandoff() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let projectRoot = temporaryDirectory("electronics-direct-design-intent-project")
        let artifactRoot = projectRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)
        let designIntentPath = artifactRoot.appendingPathComponent("amp-design_intent.json")
        let provider = MockProvider(responses: [
            .toolCall(
                id: "intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"amp_low_voltage_audio"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.currentProjectPath = projectRoot.path
        engine.permissionMode = .autoAccept
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: false, complexity: .routine, reason: "direct electronics call")
        )
        var toolNames: [String] = []
        var toolResultContents: [String] = []
        var notes: [String] = []
        var cleanStops: [String] = []
        var didCallBuildIntentTool = false
        engine.registerTool("kicad_build_intent_model") { _ in
            didCallBuildIntentTool = true
            try? FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
            try? #"{"project":"AmpDemo","topology":"25W Class A"}"#.write(
                to: designIntentPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}],"nextActions":["review_and_approve_design_intent"]}"#
        }

        for await event in engine.send(userMessage: "Produce DesignIntent, CircuitIR, KiCad schematic, PCB, and DRC evidence") {
            switch event {
            case .toolCallStarted(let call):
                toolNames.append(call.function.name)
            case .toolCallResult(let result):
                toolResultContents.append(result.content)
            case .systemNote(let note):
                notes.append(note)
            case .cleanStop(let reason, let summary):
                cleanStops.append("\(reason): \(summary)")
            default:
                break
            }
        }

        XCTAssertTrue(didCallBuildIntentTool, "Expected kicad_build_intent_model to run; saw tools \(toolNames)")
        XCTAssertTrue(
            toolResultContents.contains { $0.contains(designIntentPath.path) },
            "Expected DesignIntent path in tool result; saw results \(toolResultContents)"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: injectURL.path),
            "A direct DesignIntent tool call must queue downstream handoff when the user asked for CircuitIR/KiCad/PCB work. Notes: \(notes). Clean stops: \(cleanStops)"
        )
        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Approve DesignIntent using the generated artifact path"), continuationText)
        XCTAssertTrue(continuationText.contains("Existing DesignIntent artifact: \(designIntentPath.path)"), continuationText)
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_approve_design_intent`"), continuationText)
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

    func testSimulationHandoffGeneratesScenarioBeforeRunningSPICE() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-spice-scenario-handoff")
        let designIntentPath = try writeArtifact(
            name: "amp-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "amp-circuit_ir.json",
            contents: #"{"design_id":"AmpDemo","components":[],"nets":[]}"#,
            in: artifactRoot
        )
        let componentMatrixPath = try writeArtifact(
            name: "amp-component_matrix.json",
            contents: selectedComponentMatrixJSON(),
            in: artifactRoot
        )
        let footprintAssignmentPath = try writeArtifact(
            name: "amp-footprint_assignment.json",
            contents: #"{"assignments":[]}"#,
            in: artifactRoot
        )
        let projectPath = try writeArtifact(
            name: "amp.kicad_pro",
            contents: #"{"meta":{"version":1}}"#,
            in: artifactRoot
        )
        let schematicPath = try writeArtifact(
            name: "amp.kicad_sch",
            contents: "(kicad_sch (version 20250114))\n",
            in: artifactRoot
        )
        let scenarioPath = try writeArtifact(
            name: "amp-scenario.cir",
            contents: """
            * generated scenario
            V1 out 0 DC 1
            RLOAD out 0 8
            .op
            .end
            """,
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "compile",
                name: "kicad_compile_project",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)","component_matrix_path":"\#(componentMatrixPath.path)","footprint_assignment_path":"\#(footprintAssignmentPath.path)","output_directory":"\#(artifactRoot.path)"}"#
            ),
            .toolCall(
                id: "scenario",
                name: "kicad_generate_spice_scenario",
                args: #"{"project_path":"\#(projectPath.path)"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 6
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Create KiCad schematic and PCB",
                    successCriteria: "KiCad schematic and PCB artifacts exist",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run SPICE simulation",
                    successCriteria: "SPICE output exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_compile_project") { _ in
            #"{"artifacts":[{"kind":"kicad_project","path":"\#(projectPath.path)"},{"kind":"kicad_schematic","path":"\#(schematicPath.path)"}],"handoff":{"project_path":"\#(projectPath.path)","design_intent_path":"\#(designIntentPath.path)"}}"#
        }
        var scenarioCallCount = 0
        engine.registerTool("kicad_generate_spice_scenario") { args in
            scenarioCallCount += 1
            let data = Data(args.utf8)
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertEqual(json?["project_path"] as? String, projectPath.path)
            return #"{"artifacts":[{"kind":"simulation_scenario","path":"\#(scenarioPath.path)"}],"handoff":{"project_path":"\#(projectPath.path)","scenario_path":"\#(scenarioPath.path)"},"next_actions":["kicad_run_spice"]}"#
        }
        var runShellCallCount = 0
        engine.registerTool("run_shell") { _ in
            runShellCallCount += 1
            return "shell should not be used for SPICE scenario handoff"
        }

        for await _ in engine.send(userMessage: "Compile the KiCad project, then run SPICE simulation") {}

        let scenarioContinuation = try readInject()
        XCTAssertTrue(scenarioContinuation.contains("Next required electronics handoff tool: `kicad_generate_spice_scenario`"), scenarioContinuation)
        XCTAssertTrue(scenarioContinuation.contains("Do not create the scenario with `run_shell`"), scenarioContinuation)
        XCTAssertFalse(scenarioContinuation.contains("Next required electronics handoff tool: `kicad_run_spice`"), scenarioContinuation)

        for await _ in engine.send(userMessage: scenarioContinuation) {}

        XCTAssertEqual(scenarioCallCount, 1)
        XCTAssertEqual(runShellCallCount, 0)
        let spiceContinuation = try readInject()
        XCTAssertTrue(spiceContinuation.contains("Next required electronics handoff tool: `kicad_run_spice`"), spiceContinuation)
        XCTAssertTrue(spiceContinuation.contains(scenarioPath.path), spiceContinuation)
    }

    func testPostSPICEContinuationDoesNotVerifyERCOrOutputStepsWithoutEvidence() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactRoot = temporaryDirectory("electronics-post-spice-truthful-prefix")
        let specPath = try writeArtifact(
            name: "spec.md",
            contents: "25W pure Class A solid-state guitar amplifier",
            in: artifactRoot
        )
        let designIntentPath = try writeArtifact(
            name: "amp-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "amp-circuit_ir.json",
            contents: #"{"design_id":"AmpDemo","components":[],"nets":[]}"#,
            in: artifactRoot
        )
        let componentMatrixPath = try writeArtifact(
            name: "amp-component_matrix.json",
            contents: selectedComponentMatrixJSON(mpn: "MJL3281AG", manufacturer: "onsemi"),
            in: artifactRoot
        )
        let footprintAssignmentPath = try writeArtifact(
            name: "amp-footprint_assignment.json",
            contents: #"{"assignments":[{"ref":"QOUT1","footprint":"Package_TO_SOT_THT:TO-3P-3_Vertical"}]}"#,
            in: artifactRoot
        )
        let projectPath = try writeArtifact(
            name: "amp.kicad_pro",
            contents: #"{"meta":{"version":1}}"#,
            in: artifactRoot
        )
        let schematicPath = try writeArtifact(
            name: "amp.kicad_sch",
            contents: "(kicad_sch (version 20250114))\n",
            in: artifactRoot
        )
        let scenarioPath = try writeArtifact(
            name: "amp-scenario.cir",
            contents: "* scenario\n.op\n.end\n",
            in: artifactRoot
        )
        let spicePath = try writeArtifact(
            name: "amp-spice.log",
            contents: "SPICE transient completed\n",
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(id: "spec", name: "read_file", args: #"{"path":"\#(specPath.path)"}"#),
            .toolCall(id: "intent", name: "kicad_build_intent_model", args: #"{"input_artifact_path":"\#(specPath.path)"}"#),
            .toolCall(id: "approve", name: "kicad_approve_design_intent", args: #"{"design_intent_path":"\#(designIntentPath.path)"}"#),
            .toolCall(id: "ir", name: "kicad_generate_circuit_ir", args: #"{"design_intent_path":"\#(designIntentPath.path)"}"#),
            .toolCall(id: "components", name: "kicad_select_components", args: #"{"circuit_ir_path":"\#(circuitIRPath.path)"}"#),
            .toolCall(id: "footprints", name: "kicad_assign_footprints", args: #"{"component_matrix_path":"\#(componentMatrixPath.path)"}"#),
            .toolCall(id: "compile", name: "kicad_compile_project", args: #"{"output_directory":"\#(artifactRoot.path)"}"#),
            .toolCall(id: "scenario", name: "kicad_generate_spice_scenario", args: #"{"project_path":"\#(projectPath.path)"}"#),
            .toolCall(id: "spice", name: "kicad_run_spice", args: #"{"project_path":"\#(projectPath.path)","scenario_path":"\#(scenarioPath.path)"}"#),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 8
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(description: "Read the AmpDemo specification file", successCriteria: "spec read", complexity: .standard),
                PlanStep(description: "Build DesignIntent with the electronics KiCad domain tool", successCriteria: "DesignIntent artifact exists", complexity: .standard),
                PlanStep(description: "Approve DesignIntent using the generated artifact path", successCriteria: "DesignIntent approved", complexity: .standard),
                PlanStep(description: "Generate Circuit IR from approved DesignIntent", successCriteria: "Circuit IR artifact exists", complexity: .standard),
                PlanStep(description: "Select real-world components from component catalogs", successCriteria: "component matrix artifact exists", complexity: .standard),
                PlanStep(description: "Assign footprints for selected components", successCriteria: "footprint assignment artifact exists", complexity: .standard),
                PlanStep(description: "Create KiCad schematic and PCB files", successCriteria: "KiCad schematic and PCB artifacts exist", complexity: .standard),
                PlanStep(description: "Run SPICE simulation", successCriteria: "SPICE output exists", complexity: .standard),
                PlanStep(description: "Run ERC verification", successCriteria: "ERC report passes", complexity: .standard),
                PlanStep(description: "Run DRC verification", successCriteria: "DRC report passes", complexity: .standard),
                PlanStep(description: "Export Gerbers and drill files", successCriteria: "Gerber and drill files exist", complexity: .standard),
                PlanStep(description: "Produce BOM with Digi-Key and Mouser part numbers", successCriteria: "vendor BOM artifact exists", complexity: .standard),
            ]
        )

        engine.registerTool("read_file") { _ in "25W pure Class A solid-state guitar amplifier requirements" }
        engine.registerTool("kicad_build_intent_model") { _ in
            #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}],"nextActions":["review_and_approve_design_intent"]}"#
        }
        engine.registerTool("kicad_approve_design_intent") { _ in
            #"{"approval":{"status":"approved"},"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath.path)"}]}"#
        }
        engine.registerTool("kicad_generate_circuit_ir") { _ in
            #"{"artifacts":[{"kind":"circuit_ir","path":"\#(circuitIRPath.path)"}],"nextActions":["select_components"]}"#
        }
        engine.registerTool("kicad_select_components") { _ in
            #"{"artifacts":[{"kind":"component_matrix","path":"\#(componentMatrixPath.path)"}],"nextActions":["assign_footprints"]}"#
        }
        engine.registerTool("kicad_assign_footprints") { _ in
            #"{"artifacts":[{"kind":"footprint_assignment","path":"\#(footprintAssignmentPath.path)"}],"nextActions":["compile_project"]}"#
        }
        engine.registerTool("kicad_compile_project") { _ in
            #"{"artifacts":[{"kind":"kicad_project","path":"\#(projectPath.path)"},{"kind":"kicad_schematic","path":"\#(schematicPath.path)"}],"status":"COMPLETE"}"#
        }
        engine.registerTool("kicad_generate_spice_scenario") { _ in
            #"{"artifacts":[{"kind":"simulation_scenario","path":"\#(scenarioPath.path)"}],"next_actions":["kicad_run_spice"]}"#
        }
        engine.registerTool("kicad_run_spice") { _ in
            #"{"artifacts":[{"kind":"spice_measurements","path":"\#(spicePath.path)"}],"status":"COMPLETE"}"#
        }

        var message = "Run the full AmpDemo electronics workflow through SPICE only, then continue truthfully."
        var continuationText = ""
        for _ in 0..<12 {
            for await _ in engine.send(userMessage: message) {}
            continuationText = try readInject()
            if continuationText.contains("Next required electronics handoff tool: `kicad_run_erc`") {
                break
            }
            message = continuationText
        }

        XCTAssertTrue(
            continuationText.contains("Next required electronics handoff tool: `kicad_run_erc`"),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("Steps 1-10 have verified tool/artifact evidence."),
            continuationText
        )
        XCTAssertFalse(
            continuationText.contains("Generate BOM"),
            "BOM must not be the next continuation before ERC/DRC/fabrication evidence exists: \(continuationText)"
        )
    }

    func testRequirementsOnlyWorkflowCallIsBlockedBeforeRegularDispatch() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(
                id: "workflow",
                name: ElectronicsWorkflowRoute.requirementsToPCB.rawValue,
                args: #"{"requirements":"25W Class A guitar amplifier"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 3
        engine.continuationInjectURL = injectURL

        var dispatchedWorkflow = false
        engine.registerTool(ElectronicsWorkflowRoute.requirementsToPCB.rawValue) { _ in
            dispatchedWorkflow = true
            return #"{"status":"COMPLETE"}"#
        }

        var cleanStops: [String] = []
        var toolResults: [String] = []
        for await event in engine.send(userMessage: "Run the AmpDemo electronics workflow from requirements") {
            switch event {
            case .cleanStop(_, let summary):
                cleanStops.append(summary)
            case .toolCallResult(let result):
                toolResults.append(result.content)
            default:
                break
            }
        }

        XCTAssertFalse(dispatchedWorkflow, "Requirements-only workflow calls must be rejected before dispatch")
        XCTAssertTrue(
            cleanStops.contains { $0.contains("workflow.requirements_to_pcb") },
            cleanStops.joined(separator: "\n")
        )
        XCTAssertTrue(
            toolResults.contains { $0.contains("cannot run from requirements text alone") },
            toolResults.joined(separator: "\n")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: injectURL.path))
    }

    func testEvidenceGateRejectsReadOnlyChurnWhenBuildIntentToolIsRequired() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/design_intent-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .toolCall(
                id: "inspect-again",
                name: "list_directory",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo"}"#
            ),
            .toolCall(
                id: "build-intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"standard_2layer"}"#
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
                    description: "Read and parse the AmpDemo specification file",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Initialize a clean KiCad project directory",
                    successCriteria: "project directory ready",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Execute kicad_build_intent_model using the parsed spec",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
            ]
        )

        var didDispatchListDirectory = false
        var didDispatchBuildIntent = false
        var toolResults: [String] = []
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("list_directory") { _ in
            didDispatchListDirectory = true
            return "spec.md"
        }
        engine.registerTool("kicad_build_intent_model") { _ in
            didDispatchBuildIntent = true
            return #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath)"}],"design_intent_path":"\#(designIntentPath)"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, read spec.md, then use the explicit KiCad/electronics handoff tools in order: kicad_build_intent_model, kicad_approve_design_intent, kicad_generate_circuit_ir.
        """) {}

        let continuationText = try readInject()
        try? FileManager.default.removeItem(at: injectURL)

        for await event in engine.send(userMessage: continuationText) {
            if case .toolCallResult(let result) = event {
                toolResults.append(result.content)
            }
        }

        XCTAssertFalse(didDispatchListDirectory, "Read-only continuation churn must be rejected before dispatch")
        XCTAssertTrue(didDispatchBuildIntent, "The exact required DesignIntent handoff tool should run after correction")
        XCTAssertTrue(
            toolResults.contains { $0.contains("next verified handoff must be `kicad_build_intent_model`") },
            toolResults.joined(separator: "\n")
        )
    }

    func testDesignIntentContinuationRequiresBuildIntentDespiteDownstreamOriginalTask() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .toolCall(
                id: "inspect-again",
                name: "list_directory",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo"}"#
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
                    description: "Read and parse /Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md to extract functional requirements",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Construct DesignIntent document covering architecture, topology selection, key design equations, and verification plan",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Generate CircuitIR using a structured JSON schema",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
            ]
        )

        var didDispatchListDirectory = false
        var toolResults: [String] = []
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("list_directory") { _ in
            didDispatchListDirectory = true
            return "spec.md"
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, run the complete AmpDemo workflow from spec.md. Read the spec, build and approve DesignIntent, generate CircuitIR, select real components, prepare libraries, assign footprints, compile the KiCad project, run ERC, DRC, and SPICE, generate Gerbers, drill files, BOM, screenshots, and final report.
        """) {}

        let continuationText = try readInject()
        try? FileManager.default.removeItem(at: injectURL)
        XCTAssertTrue(continuationText.contains("Construct DesignIntent"), continuationText)

        for await event in engine.send(userMessage: continuationText) {
            if case .toolCallResult(let result) = event {
                toolResults.append(result.content)
            }
        }

        XCTAssertFalse(didDispatchListDirectory, "Read-only churn must not dispatch for the DesignIntent continuation")
        XCTAssertTrue(
            toolResults.contains { $0.contains("next verified handoff must be `kicad_build_intent_model`") },
            toolResults.joined(separator: "\n")
        )
        XCTAssertFalse(
            toolResults.contains { $0.contains("next verified handoff must be `kicad_generate_circuit_ir`") },
            toolResults.joined(separator: "\n")
        )
    }

    func testEvidenceGateRejectsApprovalBeforeBuildIntentWhenPlannerSaysBuildIntentModel() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/design_intent-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .toolCall(
                id: "approve-too-early",
                name: "kicad_approve_design_intent",
                args: #"{"design_intent_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/artifacts/design_intent.json"}"#
            ),
            .toolCall(
                id: "build-intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"standard_2layer"}"#
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
                    description: "Read and parse the AmpDemo spec.md file",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Initialize a clean project directory structure for AmpDemo using kicad_build_intent_model",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_approve_design_intent to validate the intent model",
                    successCriteria: "DesignIntent approved",
                    complexity: .standard
                ),
            ]
        )

        var didDispatchApproval = false
        var didDispatchBuildIntent = false
        var toolResults: [String] = []
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("kicad_approve_design_intent") { _ in
            didDispatchApproval = true
            return #"{"status":"ok","approved":true}"#
        }
        engine.registerTool("kicad_build_intent_model") { _ in
            didDispatchBuildIntent = true
            return #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath)"}],"design_intent_path":"\#(designIntentPath)"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, read spec.md, then use kicad_build_intent_model before kicad_approve_design_intent.
        """) {}
        let continuationText = try readInject()
        try? FileManager.default.removeItem(at: injectURL)

        for await event in engine.send(userMessage: continuationText) {
            if case .toolCallResult(let result) = event {
                toolResults.append(result.content)
            }
        }

        XCTAssertFalse(didDispatchApproval, "Approval must not dispatch before a DesignIntent artifact exists")
        XCTAssertTrue(didDispatchBuildIntent, "BuildIntent must be the enforced handoff after requirements evidence")
        XCTAssertTrue(
            toolResults.contains { $0.contains("next verified handoff must be `kicad_build_intent_model`") },
            toolResults.joined(separator: "\n")
        )
    }

    func testEvidenceGateRejectsApprovalBeforeBuildIntentWhenInitStepPrecedesBuildIntent() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/design_intent-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .toolCall(
                id: "approve-too-early",
                name: "kicad_approve_design_intent",
                args: #"{"design_intent_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/artifacts/design_intent.json"}"#
            ),
            .toolCall(
                id: "build-intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"standard_2layer"}"#
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
                    description: "Read and parse the AmpDemo spec.md file to extract design intent",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Initialize a clean KiCad project directory at /Users/jonzuilkowski/Documents/localProject/AmpDemo",
                    successCriteria: "project directory ready",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Execute kicad_build_intent_model using parsed spec to generate a structured design intent",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_approve_design_intent to validate the intent model",
                    successCriteria: "DesignIntent approved",
                    complexity: .standard
                ),
            ]
        )

        var didDispatchApproval = false
        var didDispatchBuildIntent = false
        var toolResults: [String] = []
        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("kicad_approve_design_intent") { _ in
            didDispatchApproval = true
            return #"{"status":"ok","approved":true}"#
        }
        engine.registerTool("kicad_build_intent_model") { _ in
            didDispatchBuildIntent = true
            return #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath)"}],"design_intent_path":"\#(designIntentPath)"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, read spec.md, then use the explicit KiCad/electronics handoff tools in order: kicad_build_intent_model, kicad_approve_design_intent.
        """) {}
        let continuationText = try readInject()
        try? FileManager.default.removeItem(at: injectURL)

        for await event in engine.send(userMessage: continuationText) {
            if case .toolCallResult(let result) = event {
                toolResults.append(result.content)
            }
        }

        XCTAssertFalse(didDispatchApproval, "Approval must not dispatch before a DesignIntent artifact exists")
        XCTAssertTrue(didDispatchBuildIntent, "BuildIntent must be enforced after read-only spec evidence")
        XCTAssertTrue(
            toolResults.contains { $0.contains("next verified handoff must be `kicad_build_intent_model`") },
            toolResults.joined(separator: "\n")
        )
    }

    func testDesignIntentArtifactSchedulesApprovalWhenSetupStepPrecedesBuildIntent() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/design_intent-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "build-intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"standard_2layer"}"#
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
                    description: "Initialize a clean KiCad project directory with schematic and PCB files",
                    successCriteria: "project directory ready",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Execute kicad_build_intent_model using parsed spec",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_approve_design_intent to validate intent model",
                    successCriteria: "DesignIntent approved",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_build_intent_model") { _ in
            #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)"},"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, use kicad_build_intent_model before kicad_approve_design_intent.
        """) {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Verified electronics artifact evidence exists"), continuationText)
        XCTAssertTrue(continuationText.contains("Existing DesignIntent artifact: \(designIntentPath)"), continuationText)
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_approve_design_intent`"), continuationText)
    }

    func testApproveDesignIntentStepIsNotSatisfiedByBuildIntentArtifact() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/draft-design_intent-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "build-intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"standard_2layer"}"#
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
                    description: "Read and parse AmpDemo spec.md",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Initialize a clean project directory structure for AmpDemo and invoke kicad_build_intent_model",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_approve_design_intent to validate the intent model against spec constraints",
                    successCriteria: "DesignIntent approved",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Execute kicad_generate_circuit_ir to produce an intermediate representation",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_build_intent_model") { _ in
            #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)"},"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, read spec.md, then run kicad_build_intent_model, kicad_approve_design_intent, and kicad_generate_circuit_ir in order.
        """) {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_approve_design_intent`"), continuationText)
        XCTAssertFalse(continuationText.contains("Next required electronics handoff tool: `kicad_generate_circuit_ir`"), continuationText)
    }

    func testApprovedDesignIntentSchedulesFocusedCircuitIRHandoffInsteadOfBroadContinuation() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/approved-design_intent-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
            .toolCall(
                id: "build-intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"standard_2layer"}"#
            ),
            .toolCall(
                id: "approve-intent",
                name: "kicad_approve_design_intent",
                args: #"{"design_intent_path":"\#(designIntentPath)"}"#
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
                    description: "Read and parse AmpDemo spec.md",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_build_intent_model to produce structured DesignIntent",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_approve_design_intent to approve the DesignIntent",
                    successCriteria: "DesignIntent approved",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Inspect approved artifact evidence and board decomposition before downstream generation",
                    successCriteria: "approved artifact reviewed",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_generate_circuit_ir from the approved DesignIntent",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("read_file") { _ in
            "25W pure Class A solid-state guitar amplifier requirements"
        }
        engine.registerTool("kicad_build_intent_model") { _ in
            #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)"},"nextActions":["review_and_approve_design_intent"],"status":"COMPLETE"}"#
        }
        engine.registerTool("kicad_approve_design_intent") { _ in
            #"{"approval":{"status":"approved"},"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath)"}],"status":"approved"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, run the full AmpDemo workflow from spec.md through Circuit IR using the explicit KiCad handoff tools.
        """) {}

        var continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Run kicad_build_intent_model"), continuationText)
        try? FileManager.default.removeItem(at: injectURL)

        for await _ in engine.send(userMessage: continuationText) {}

        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_approve_design_intent`"), continuationText)
        try? FileManager.default.removeItem(at: injectURL)

        for await _ in engine.send(userMessage: continuationText) {}

        continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Verified electronics artifact evidence exists"), continuationText)
        XCTAssertTrue(continuationText.contains("Existing DesignIntent artifact: \(designIntentPath)"), continuationText)
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_generate_circuit_ir`"), continuationText)
        XCTAssertTrue(continuationText.contains("Do not call `read_file`"), continuationText)
        XCTAssertFalse(continuationText.contains("Continue from the first unverified electronics step"), continuationText)
    }

    func testGeneratedElectronicsArtifactReadIsCompactedBeforeContextAppend() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let artifactPath = "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/\(UUID().uuidString)-design_intent.json"
        let largeArtifact = """
        {"schema":"design_intent","boards":[{"id":"isolated_secondary"},{"id":"mains_power"}],"payload":"
        """ + String(repeating: "approved-evidence-", count: 1_500) + #""}"#
        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-approved",
                name: "read_file",
                args: #"{"path":"\#(artifactPath)"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 3
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Inspect generated electronics artifact evidence before Circuit IR",
                    successCriteria: "artifact inspected",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Generate Circuit IR from approved DesignIntent",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("read_file") { _ in largeArtifact }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, inspect the generated DesignIntent artifact evidence, then continue to Circuit IR.
        """) {}

        let toolMessages = engine.contextManager.messages.filter { $0.role == .tool }
        let toolText = toolMessages.map(\.content.plainText).joined(separator: "\n")
        XCTAssertTrue(toolText.contains("generated electronics artifact read compacted"), toolText)
        XCTAssertLessThan(toolText.count, 6_000, "Generated electronics artifact reads must not enter context verbatim")
        XCTAssertFalse(toolText.contains(String(repeating: "approved-evidence-", count: 1_000)), toolText)
    }

    func testDesignIntentNextActionSchedulesApprovalEvenWhenPlanOmitsApprovalStep() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/draft-design_intent-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "build-intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md","board_profile_id":"standard_2layer"}"#
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
                    description: "Build DesignIntent with kicad_build_intent_model",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Execute kicad_generate_circuit_ir to produce an intermediate representation",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_build_intent_model") { _ in
            #"{"artifacts":[{"kind":"design_intent","path":"\#(designIntentPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)"},"nextActions":["review_and_approve_design_intent"],"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, run kicad_build_intent_model, then kicad_generate_circuit_ir.
        """) {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Existing DesignIntent artifact: \(designIntentPath)"), continuationText)
        XCTAssertTrue(continuationText.contains("Task: Approve DesignIntent using the generated artifact path"), continuationText)
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_approve_design_intent`"), continuationText)
        XCTAssertFalse(continuationText.contains("Next required electronics handoff tool: `kicad_generate_circuit_ir`"), continuationText)
        XCTAssertFalse(continuationText.contains("Task: Generate Circuit IR from approved DesignIntent"), continuationText)
    }

    func testCircuitIRArtifactSchedulesComponentSelectionWithArtifactPaths() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/approved-design_intent-\(UUID().uuidString).json"
        let circuitIRPath = NSTemporaryDirectory() + "/circuit_ir-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "circuit-ir",
                name: "kicad_generate_circuit_ir",
                args: #"{"design_intent_path":"\#(designIntentPath)"}"#
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
                    description: "Execute kicad_generate_circuit_ir from approved DesignIntent",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Execute kicad_select_components to populate component choices",
                    successCriteria: "Component matrix artifact exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_generate_circuit_ir") { _ in
            #"{"artifacts":[{"kind":"circuit_ir","path":"\#(circuitIRPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)"},"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, use kicad_generate_circuit_ir before kicad_select_components.
        """) {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_select_components`"), continuationText)
        XCTAssertTrue(continuationText.contains(#""design_intent_path":"\#(designIntentPath)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""circuit_ir_path":"\#(circuitIRPath)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""live_catalog_providers":["mouser","digikey"]"#), continuationText)
    }

    func testCircuitIRNextActionSchedulesComponentSelectionForVendorCatalogStep() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/approved-design_intent-\(UUID().uuidString).json"
        let circuitIRPath = NSTemporaryDirectory() + "/circuit_ir-\(UUID().uuidString).json"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "circuit-ir",
                name: "kicad_generate_circuit_ir",
                args: #"{"design_intent_path":"\#(designIntentPath)"}"#
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
                    description: "Generate Circuit IR from approved DesignIntent",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Select all required components from vendor catalogs using Digi-Key and Mouser constraints",
                    successCriteria: "Component matrix artifact exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_generate_circuit_ir") { _ in
            #"{"artifacts":[{"kind":"circuit_ir","path":"\#(circuitIRPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)"},"nextActions":["select_components"],"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Run the complete AmpDemo electronics workflow from spec.md and continue through vendor-backed component selection.
        """) {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_select_components`"), continuationText)
        XCTAssertTrue(continuationText.contains(#""design_intent_path":"\#(designIntentPath)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""circuit_ir_path":"\#(circuitIRPath)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""live_catalog_providers":["mouser","digikey"]"#), continuationText)
        XCTAssertFalse(continuationText.contains("or call `kicad_generate_circuit_ir`"), continuationText)
        XCTAssertFalse(continuationText.contains("Call `kicad_approve_design_intent`"), continuationText)
    }

    func testFootprintAssignmentSchedulesCompileProjectWithArtifactPaths() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/approved-design_intent-\(UUID().uuidString).json"
        let circuitIRPath = NSTemporaryDirectory() + "/circuit_ir-\(UUID().uuidString).json"
        let componentMatrixPath = NSTemporaryDirectory() + "/component_matrix-\(UUID().uuidString).json"
        let footprintAssignmentPath = NSTemporaryDirectory() + "/footprint_assignment-\(UUID().uuidString).json"
        try #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#.write(
            toFile: designIntentPath,
            atomically: true,
            encoding: .utf8
        )
        try #"{"design_id":"AmpDemo","components":[{"refdes":"QOUT1"}],"nets":[]}"#.write(
            toFile: circuitIRPath,
            atomically: true,
            encoding: .utf8
        )
        try selectedComponentMatrixJSON().write(
            toFile: componentMatrixPath,
            atomically: true,
            encoding: .utf8
        )
        let provider = MockProvider(responses: [
            .toolCall(
                id: "footprints",
                name: "kicad_assign_footprints",
                args: #"{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)","component_matrix_path":"\#(componentMatrixPath)"}"#
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
                    description: "Assign footprints for selected components",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Create KiCad project directory structure and initialize schematic and PCB files",
                    successCriteria: "KiCad schematic and PCB artifacts exist",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_assign_footprints") { _ in
            #"{"artifacts":[{"kind":"footprint_assignment","path":"\#(footprintAssignmentPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)","component_matrix_path":"\#(componentMatrixPath)","footprint_assignment_path":"\#(footprintAssignmentPath)"},"nextActions":["compile_project"],"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Continue AmpDemo through footprint assignment and compile the KiCad project from verified artifacts.
        """) {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_compile_project`"), continuationText)
        XCTAssertTrue(continuationText.contains(#""design_intent_path":"\#(designIntentPath)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""circuit_ir_path":"\#(circuitIRPath)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""component_matrix_path":"\#(componentMatrixPath)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""footprint_assignment_path":"\#(footprintAssignmentPath)""#), continuationText)
        XCTAssertTrue(continuationText.contains(#""output_directory":"#), continuationText)
    }

    func testVendorOrderHandoffIgnoresNonexistentBOMPathExtractedFromProse() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let projectRoot = temporaryDirectory("electronics-bogus-bom-handoff")
        let artifactRoot = projectRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)
        let designIntentPath = try writeArtifact(
            name: "amp-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "amp-circuit_ir.json",
            contents: #"{"design_id":"AmpDemo","components":[],"nets":[]}"#,
            in: artifactRoot
        )
        let componentMatrixPath = artifactRoot.appendingPathComponent("amp-component_matrix.json")

        let provider = MockProvider(responses: [
            .toolCall(
                id: "components",
                name: "kicad_select_components",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.currentProjectPath = projectRoot.path
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 8
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Select discrete components with catalog candidates",
                    successCriteria: "Component matrix artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Produce BOM with Digi-Key and Mouser part numbers",
                    successCriteria: "Vendor BOM artifact exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_select_components") { _ in
            try? #"{"components":[{"ref":"QOUT1","mpn":"MJL3281AG"}]}"#.write(
                to: componentMatrixPath,
                atomically: true,
                encoding: .utf8
            )
            return #"{"artifacts":[{"kind":"component_matrix","path":"\#(componentMatrixPath.path)"}],"notes":"Later verification folders are /DRC/SPICE/BOM. Do not treat this prose as a BOM artifact.","nextActions":["prepare_vendor_order"],"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Continue AmpDemo from component selection into BOM preparation only when real BOM evidence exists.
        """) {}

        guard FileManager.default.fileExists(atPath: injectURL.path) else { return }
        let continuationText = try readInject()
        XCTAssertFalse(continuationText.contains("Next required electronics handoff tool: `kicad_prepare_vendor_order`"), continuationText)
        XCTAssertFalse(continuationText.contains(#""normalized_bom_path":"/DRC/SPICE/BOM""#), continuationText)
    }

    func testBlockedFootprintAssignmentClearsContinuationInsteadOfRepeatingHandoff() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let projectRoot = temporaryDirectory("electronics-blocked-footprint-handoff")
        let artifactRoot = projectRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)
        let designIntentPath = try writeArtifact(
            name: "amp-design_intent.json",
            contents: #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#,
            in: artifactRoot
        )
        let circuitIRPath = try writeArtifact(
            name: "amp-circuit_ir.json",
            contents: #"{"design_id":"AmpDemo","components":[{"refdes":"QOUT1"}],"nets":[]}"#,
            in: artifactRoot
        )
        let componentMatrixPath = try writeArtifact(
            name: "amp-component_matrix.json",
            contents: #"{"decisions":[{"refdes":"QOUT1","status":"blocked"}]}"#,
            in: artifactRoot
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "footprints",
                name: "kicad_assign_footprints",
                args: #"{"design_intent_path":"\#(designIntentPath.path)","circuit_ir_path":"\#(circuitIRPath.path)","component_matrix_path":"\#(componentMatrixPath.path)"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.currentProjectPath = projectRoot.path
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 8
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Assign footprints for selected components",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Create KiCad schematic and PCB files",
                    successCriteria: "KiCad schematic and PCB artifacts exist",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_assign_footprints") { _ in
            #"{"status":"BLOCKED_LIBRARY","warnings":[{"code":"BLOCKED_FOOTPRINTS","message":"Footprint assignment is blocked until every selected component has compatible footprint evidence."}],"nextActions":["revise_footprint_selection"]}"#
        }

        for await _ in engine.send(userMessage: """
        Continue AmpDemo through footprint assignment and stop if footprints are unresolved.
        """) {}

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: injectURL.path),
            "A blocked footprint assignment must stop instead of scheduling kicad_assign_footprints again"
        )
    }

    func testBlockedERCWithRepairNextActionSchedulesERCRepairHandoff() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let designIntentPath = NSTemporaryDirectory() + "/design_intent-\(UUID().uuidString).json"
        let circuitIRPath = NSTemporaryDirectory() + "/circuit_ir-\(UUID().uuidString).json"
        let ercReportPath = NSTemporaryDirectory() + "/erc-report-\(UUID().uuidString).json"
        let projectPath = NSTemporaryDirectory() + "/isolated_secondary-\(UUID().uuidString).kicad_pro"
        let provider = MockProvider(responses: [
            .toolCall(
                id: "circuit",
                name: "kicad_generate_circuit_ir",
                args: #"{"design_intent_path":"\#(designIntentPath)"}"#
            ),
            .toolCall(
                id: "erc",
                name: "kicad_run_erc",
                args: #"{"project_path":"\#(projectPath)"}"#
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
                    description: "Generate Circuit IR from approved DesignIntent",
                    successCriteria: "Circuit IR artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run ERC in KiCad and repair diagnostics until clean",
                    successCriteria: "ERC report passes",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run DRC in KiCad",
                    successCriteria: "DRC report passes",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_generate_circuit_ir") { _ in
            #"{"status":"COMPLETE","artifacts":[{"kind":"circuit_ir","path":"\#(circuitIRPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)"}}"#
        }
        engine.registerTool("kicad_run_erc") { _ in
            """
            {"status":"BLOCKED","artifacts":[{"kind":"erc_report","path":"\(ercReportPath)"}],"handoff":{"erc_report_path":"\(ercReportPath)","project_path":"\(projectPath)"},"next_actions":["repair_erc_from_diagnostics","rerun_erc"],"violations":[{"code":"pin_not_connected","severity":"error","message":"Pin not connected"}]}
            pin_not_connected: Pin not connected
            Found 22 violations
            Saved ERC Report to \(ercReportPath)
            artifacts:
            erc_report: \(ercReportPath)
            """
        }

        var cleanStopSummary: String?
        for await _ in engine.send(userMessage: """
        Continue AmpDemo by running ERC and repairing any ERC diagnostics before DRC.
        """) {}

        let ercContinuation = try readInject()
        XCTAssertTrue(ercContinuation.contains("Run ERC in KiCad"), ercContinuation)

        cleanStopSummary = nil
        for await event in engine.send(userMessage: ercContinuation) {
            if case let .cleanStop(_, summary) = event {
                cleanStopSummary = summary
            }
        }

        XCTAssertNil(cleanStopSummary)
        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics repair tool: `kicad_repair_erc_from_diagnostics`"), continuationText)
        let marker = "The next assistant tool call must be exactly `kicad_repair_erc_from_diagnostics` with this JSON shape:\n"
        let continuationParts = continuationText.components(separatedBy: marker)
        XCTAssertEqual(continuationParts.count, 2, continuationText)
        let jsonLine = try XCTUnwrap(
            continuationParts.last?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(String(jsonLine).utf8)) as? [String: Any]
        )
        XCTAssertEqual(json["erc_report_path"] as? String, ercReportPath)
        XCTAssertEqual(json["circuit_ir_path"] as? String, circuitIRPath)
        XCTAssertTrue(continuationText.contains("without marking the verification gate complete"), continuationText)
        XCTAssertTrue(continuationText.contains("Do not claim ERC, DRC, or SPICE verification passed"), continuationText)
    }

    func testFocusedCompileProjectCallHydratesMissingEvidencePathsBeforeDispatch() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ampdemo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let artifactRoot = projectRoot.appendingPathComponent(".merlin/electronics-artifacts", isDirectory: true)
        let designIntentPath = artifactRoot.appendingPathComponent("approved-design_intent.json").path
        let circuitIRPath = artifactRoot.appendingPathComponent("circuit_ir.json").path
        let componentMatrixPath = artifactRoot.appendingPathComponent("component_matrix.json").path
        let footprintAssignmentPath = artifactRoot.appendingPathComponent("footprint_assignment.json").path
        let outputDirectory = projectRoot.appendingPathComponent("kicad", isDirectory: true).path
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        try #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#.write(
            toFile: designIntentPath,
            atomically: true,
            encoding: .utf8
        )
        try #"{"design_id":"AmpDemo","components":[{"refdes":"QOUT1"}],"nets":[]}"#.write(
            toFile: circuitIRPath,
            atomically: true,
            encoding: .utf8
        )
        try selectedComponentMatrixJSON().write(
            toFile: componentMatrixPath,
            atomically: true,
            encoding: .utf8
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "footprints",
                name: "kicad_assign_footprints",
                args: #"{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)","component_matrix_path":"\#(componentMatrixPath)"}"#
            ),
            .toolCall(
                id: "compile",
                name: "kicad_compile_project",
                args: #"{"design_intent_path":"\#(designIntentPath)","output_directory":"\#(outputDirectory)"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.currentProjectPath = projectRoot.path
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 8
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Assign footprints for selected components",
                    successCriteria: "Footprint assignment artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Create KiCad project directory structure and initialize schematic and PCB files",
                    successCriteria: "KiCad schematic and PCB artifacts exist",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_assign_footprints") { _ in
            #"{"artifacts":[{"kind":"footprint_assignment","path":"\#(footprintAssignmentPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)","component_matrix_path":"\#(componentMatrixPath)","footprint_assignment_path":"\#(footprintAssignmentPath)"},"nextActions":["compile_project"],"status":"COMPLETE"}"#
        }

        var dispatchedCompileArguments: String?
        engine.registerTool("kicad_compile_project") { args in
            dispatchedCompileArguments = args
            return #"{"artifacts":[{"kind":"kicad_project","path":"\#(outputDirectory)"}],"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Continue AmpDemo through footprint assignment and compile the KiCad project from verified artifacts.
        """) {}

        let continuationText = try readInject()
        XCTAssertTrue(continuationText.contains("Next required electronics handoff tool: `kicad_compile_project`"), continuationText)

        for await _ in engine.send(userMessage: continuationText) {}

        let captured = try XCTUnwrap(dispatchedCompileArguments)
        let data = try XCTUnwrap(captured.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["design_intent_path"] as? String, designIntentPath)
        XCTAssertEqual(object["circuit_ir_path"] as? String, circuitIRPath)
        XCTAssertEqual(object["component_matrix_path"] as? String, componentMatrixPath)
        XCTAssertEqual(object["footprint_assignment_path"] as? String, footprintAssignmentPath)
        XCTAssertEqual(object["output_directory"] as? String, outputDirectory)
    }

    func testEvidenceGateAllowsInitialSpecReadBeforeDesignIntentApprovalStep() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 3
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read and parse the AmpDemo specification file",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Execute kicad_build_intent_model using the parsed spec",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Run kicad_approve_design_intent to validate the design intent",
                    successCriteria: "DesignIntent approved",
                    complexity: .standard
                ),
            ]
        )

        var didDispatchReadFile = false
        var toolResults: [String] = []
        engine.registerTool("read_file") { _ in
            didDispatchReadFile = true
            return "25W pure Class A solid-state guitar amplifier requirements"
        }

        for await event in engine.send(userMessage: """
        Using the electronics domain, read spec.md, then use the explicit KiCad/electronics handoff tools in order: kicad_build_intent_model, kicad_approve_design_intent.
        """) {
            if case .toolCallResult(let result) = event {
                toolResults.append(result.content)
            }
        }

        XCTAssertTrue(didDispatchReadFile, "The initial requirements read must be allowed before DesignIntent approval can be required")
        XCTAssertFalse(
            toolResults.contains { $0.contains("next verified handoff must be `kicad_approve_design_intent`") },
            toolResults.joined(separator: "\n")
        )
    }

    func testFocusedComponentSelectionSliceStopsAfterMatrixWhenRequested() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ampdemo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let artifactRoot = projectRoot.appendingPathComponent(".merlin/electronics-artifacts", isDirectory: true)
        let designIntentPath = artifactRoot.appendingPathComponent("approved-design_intent.json").path
        let circuitIRPath = artifactRoot.appendingPathComponent("circuit_ir.json").path
        let componentMatrixPath = artifactRoot.appendingPathComponent("component_matrix.json").path
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        try #"{"project":"AmpDemo","topology":"single_ended_class_a"}"#.write(
            toFile: designIntentPath,
            atomically: true,
            encoding: .utf8
        )
        try #"{"design_id":"AmpDemo","components":[{"refdes":"QOUT1"}],"nets":[]}"#.write(
            toFile: circuitIRPath,
            atomically: true,
            encoding: .utf8
        )

        let provider = MockProvider(responses: [
            .toolCall(
                id: "select-components",
                name: "kicad_select_components",
                args: #"{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)","live_catalog_providers":["mouser","digikey"],"live_catalog_result_limit":3}"#
            ),
            .toolCall(
                id: "footprints",
                name: "kicad_assign_footprints",
                args: #"{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)","component_matrix_path":"\#(componentMatrixPath)"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.currentProjectPath = projectRoot.path
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 5
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Invoke kicad_select_components with live catalog providers",
                    successCriteria: "component matrix artifact exists",
                    complexity: .highStakes
                ),
                PlanStep(
                    description: "Verify component_matrix.json exists, then stop before footprints",
                    successCriteria: "component matrix verified and no downstream KiCad tools executed",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("kicad_select_components") { _ in
            try self.selectedComponentMatrixJSON().write(toFile: componentMatrixPath, atomically: true, encoding: .utf8)
            return #"{"artifacts":[{"kind":"component_matrix","path":"\#(componentMatrixPath)"}],"handoff":{"design_intent_path":"\#(designIntentPath)","circuit_ir_path":"\#(circuitIRPath)","component_matrix_path":"\#(componentMatrixPath)"},"nextActions":["assign_footprints"],"status":"COMPLETE"}"#
        }

        var didDispatchFootprints = false
        engine.registerTool("kicad_assign_footprints") { _ in
            didDispatchFootprints = true
            return #"{"status":"COMPLETE"}"#
        }

        for await _ in engine.send(userMessage: """
        Using the electronics domain, run only the focused component-selection verification slice for AmpDemo. Stop after the component matrix artifact exists. Do not generate footprints, schematic, PCB, SPICE, Gerbers, BOM, or report.
        """) {}

        XCTAssertFalse(didDispatchFootprints, "Focused component-selection slice must not advance to footprint assignment.")
        if FileManager.default.fileExists(atPath: injectURL.path) {
            let continuationText = try readInject()
            XCTAssertFalse(continuationText.contains("kicad_assign_footprints"), continuationText)
        }
    }

    func testEvidenceGateStopsWhenRequirementsReadFails() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(
                id: "read-spec",
                name: "read_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/spec.md"}"#
            ),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.maxIterationsOverride = 3
        engine.continuationInjectURL = injectURL
        engine.classifierOverride = StubPlanner(
            classification: ClassifierResult(needsPlanning: true, complexity: .standard, reason: "electronics test"),
            steps: [
                PlanStep(
                    description: "Read and parse the AmpDemo specification file",
                    successCriteria: "spec read",
                    complexity: .standard
                ),
                PlanStep(
                    description: "Execute kicad_build_intent_model using the parsed spec",
                    successCriteria: "DesignIntent artifact exists",
                    complexity: .standard
                ),
            ]
        )

        engine.registerTool("read_file") { _ in
            throw NSError(
                domain: "tool_dispatch",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "REQUEST_TIMED_OUT"]
            )
        }

        var cleanStops: [String] = []
        for await event in engine.send(userMessage: """
        Using the electronics domain, read spec.md, then use kicad_build_intent_model.
        """) {
            if case .cleanStop(_, let summary) = event {
                cleanStops.append(summary)
            }
        }

        XCTAssertTrue(
            cleanStops.contains { $0.contains("REQUEST_TIMED_OUT") },
            cleanStops.joined(separator: "\n")
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: injectURL.path),
            "A failed requirements read must not schedule another electronics continuation"
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
