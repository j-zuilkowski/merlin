// ParallelWorkerTests.swift
// Phase 199a — failing tests for parallel worker execution.
import XCTest
@testable import Merlin

@MainActor
final class ParallelWorkerTests: XCTestCase {

    // MARK: - PlanStep.parallelSafe

    /// PlanStep must carry a parallelSafe flag.
    /// FAILS before 199b — PlanStep has no parallelSafe property.
    func test_planStep_hasParallelSafeFlag() {
        let step = PlanStep(description: "edit file A",
                            successCriteria: "file A modified",
                            complexity: .standard,
                            parallelSafe: true)
        XCTAssertTrue(step.parallelSafe)
    }

    // MARK: - PlannerEngine step parsing

    /// parseSteps must extract parallel_safe annotations from planner output.
    /// FAILS before 199b — parseSteps ignores parallel_safe field.
    func test_parseSteps_readsParallelSafeAnnotation() {
        let planner = PlannerEngine()
        let raw = """
        [
          {"step": "Edit README", "success_criteria": "README updated", "complexity": "standard", "parallel_safe": true},
          {"step": "Run tests", "success_criteria": "tests pass", "complexity": "standard", "parallel_safe": false}
        ]
        """
        let steps = planner.parseStepsForTesting(from: raw)
        XCTAssertEqual(steps.count, 2)
        XCTAssertTrue(steps[0].parallelSafe, "README edit should be parallel-safe")
        XCTAssertFalse(steps[1].parallelSafe, "test run depends on prior edit — not parallel-safe")
    }

    /// parseSteps defaults parallelSafe to false when the annotation is absent, and
    /// must not drop a step whose complexity uses the snake_case "high_stakes" form.
    func test_parseSteps_defaultsParallelSafeToFalse() {
        let planner = PlannerEngine()
        let raw = """
        [{"step": "Deploy", "success_criteria": "deployed", "complexity": "high_stakes"}]
        """
        let steps = planner.parseStepsForTesting(from: raw)
        XCTAssertEqual(steps.count, 1,
                       "a step with complexity \"high_stakes\" must not be dropped")
        guard let first = steps.first else { return }
        XCTAssertFalse(first.parallelSafe,
                       "missing parallel_safe annotation must default to false")
    }

    /// ComplexityTier must decode the snake_case "high_stakes" form, not only the
    /// hyphenated raw value.
    func test_complexityTier_decodesSnakeCaseHighStakes() throws {
        let data = Data("\"high_stakes\"".utf8)
        let tier = try JSONDecoder().decode(ComplexityTier.self, from: data)
        XCTAssertEqual(tier, .highStakes)
    }

    /// An unrecognised complexity string decodes to .standard rather than throwing.
    func test_complexityTier_unknownValueDecodesToStandard() throws {
        let data = Data("\"banana\"".utf8)
        let tier = try JSONDecoder().decode(ComplexityTier.self, from: data)
        XCTAssertEqual(tier, .standard)
    }

    // MARK: - Parallel spawn_agent dispatch

    /// handleSpawnAgents must launch all subagents concurrently.
    /// Concurrency is verified by ensuring all agents report start events before any completes.
    /// FAILS before 199b — handleSpawnAgents() does not exist.
    func test_handleSpawnAgents_startsAllBeforeAnyCompletes() async throws {
        let engine = EngineFactory.make()

        // Create 3 spawn calls
        let spawnCalls = (1...3).map { i -> ToolCall in
            let args = #"{"agent":"explorer","prompt":"task \#(i)"}"#
            return ToolCall(id: "s\(i)", type: "function",
                            function: FunctionCall(name: "spawn_agent", arguments: args))
        }

        var events: [AgentEvent] = []
        let stream = AsyncStream<AgentEvent> { cont in
            Task {
                await engine.handleSpawnAgents(spawnCalls, depth: 0, continuation: cont)
                cont.finish()
            }
        }

        for await event in stream {
            events.append(event)
        }

        let startCount = events.filter {
            if case .subagentStarted = $0 { return true }; return false
        }.count
        XCTAssertEqual(startCount, 3, "all 3 agents must have been started")
    }

    // MARK: - Parallel step batching

    /// Adjacent parallel-safe steps must be grouped into one continuation batch.
    /// FAILS before 199b — groupParallelSteps() does not exist.
    func test_parallelSafeSteps_areGroupedIntoBatch() {
        let engine = EngineFactory.make()

        let steps = [
            PlanStep(description: "edit A", successCriteria: "", complexity: .standard, parallelSafe: true),
            PlanStep(description: "edit B", successCriteria: "", complexity: .standard, parallelSafe: true),
            PlanStep(description: "run tests", successCriteria: "", complexity: .standard, parallelSafe: false)
        ]

        let batches = engine.groupParallelSteps(steps)

        // First batch: steps A and B (both parallel-safe)
        // Second batch: run tests (sequential)
        XCTAssertEqual(batches.count, 2,
                       "parallel-safe steps must be grouped; sequential step is its own batch")
        XCTAssertEqual(batches[0].count, 2)
        XCTAssertEqual(batches[1].count, 1)
    }
}
