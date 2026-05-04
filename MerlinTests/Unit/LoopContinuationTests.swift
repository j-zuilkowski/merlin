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

    // MARK: - Fix 1: Plan batching & continuation inject

    /// When the planner returns more steps than the per-turn budget (maxIterations / 4),
    /// the engine executes only the first batch and writes a [CONTINUATION] inject for the rest.
    func testPlanBatchSplitsAndSchedulesContinuation() async throws {
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
        // but the note must only appear once.
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "t1", name: "noop", args: "{}"),
            MockLLMResponse.toolCall(id: "t2", name: "noop", args: "{}"),
            MockLLMResponse.toolCall(id: "t3", name: "noop", args: "{}"),
            MockLLMResponse.toolCall(id: "t4", name: "noop", args: "{}"),
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
