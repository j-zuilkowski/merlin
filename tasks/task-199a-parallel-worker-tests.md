# Task 199a — Parallel Worker Execution Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 198b complete: async batch tool dispatch.

## Problem — two separate bottlenecks

### Bottleneck A: spawn_agent calls are sequential
When the model emits multiple `spawn_agent` tool calls in one response (e.g. "explore X
and explore Y simultaneously"), `handleSpawnAgent` is awaited one at a time inside a `for`
loop. Each subagent must fully complete before the next one starts, even though they are
independent actors with their own event streams.

### Bottleneck B: parallel-safe plan steps run in separate continuation turns
`PlannerEngine.decompose` returns a flat `[PlanStep]` with `stepsPerTurn = 1`. Steps that
could run concurrently (e.g. "edit file A" and "edit file B") are deferred to sequential
continuation turns. There is no way for the planner to signal that two steps are independent.

## Fix (implemented in 199b)

**Bottleneck A — parallel spawn dispatch:**
Separate `spawn_agent` calls from regular tool calls as before, but dispatch them all via
`withTaskGroup`. Each task starts the subagent and forwards its event stream to the shared
continuation concurrently. All tasks are awaited before the outer loop continues.

**Bottleneck B — parallelSafe PlanStep annotation:**
Add `parallelSafe: Bool` to `PlanStep`. Update the planner decompose prompt to emit a
`parallel_safe:` annotation per step. Update `parseSteps` to parse it. In `AgenticEngine`,
group adjacent parallel-safe steps into a single continuation batch instead of enforcing
`stepsPerTurn = 1` for them.

## New surface in task 199b
- `PlanStep.parallelSafe: Bool` — true when the step has no file/state dependency on siblings
- `PlannerEngine.parseSteps(from:)` parses `parallel_safe: true/false` from planner output
- `AgenticEngine.handleSpawnAgents(_ calls: [ToolCall], depth:, continuation:)` — dispatches
  all spawn_agent calls concurrently; replaces the sequential per-call `handleSpawnAgent` loop
- `AgenticEngine` continuation batching groups parallel-safe steps together (up to
  `maxParallelSteps = 4` per batch)

TDD coverage:
  File — ParallelWorkerTests.swift: 5 tests

---

## Write to: MerlinTests/Unit/ParallelWorkerTests.swift

```swift
// ParallelWorkerTests.swift
// Task 199a — failing tests for parallel worker execution.
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

    /// parseSteps defaults parallelSafe to false when annotation is absent.
    /// FAILS before 199b — parseStepsForTesting() does not exist.
    func test_parseSteps_defaultsParallelSafeToFalse() {
        let planner = PlannerEngine()
        let raw = """
        [{"step": "Deploy", "success_criteria": "deployed", "complexity": "high_stakes"}]
        """
        let steps = planner.parseStepsForTesting(from: raw)
        XCTAssertEqual(steps.count, 1)
        XCTAssertFalse(steps[0].parallelSafe,
                       "missing parallel_safe annotation must default to false")
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
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `PlanStep.parallelSafe`, `parseStepsForTesting()`,
`handleSpawnAgents()`, and `groupParallelSteps()` do not exist yet.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ParallelWorkerTests.swift
git commit -m "Task 199a — ParallelWorkerTests (failing)"
```
