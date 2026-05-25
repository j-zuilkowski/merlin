# Phase 103a — PlannerEngine Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 102b complete: CriticEngine (two-stage) in place.

New surface introduced in phase 103b:
  - `ComplexityTier` enum — `.routine` / `.standard` / `.highStakes`
  - `ClassifierResult` struct — `needsPlanning: Bool`, `complexity: ComplexityTier`, `reason: String`
  - `PlannerEngine` actor — classifies tasks, decomposes plans, routes slots
  - `PlannerEngine.classify(message:domain:)` → `ClassifierResult`
  - `PlannerEngine.decompose(task:context:)` → `[PlanStep]`
  - `PlanStep` struct — `description`, `successCriteria`, `complexity`
  - Tier override parsing: `#high-stakes`, `#standard`, `#routine` prefixes
  - `AppSettings` gains `maxPlanRetries: Int` and `maxLoopIterations: Int`

TDD coverage:
  File 1 — PlannerEngineTests: classify routine/standard/high-stakes, tier override parsing, decompose returns steps, plan retry limit respected

---

## Write to: MerlinTests/Unit/PlannerEngineTests.swift

```swift
import XCTest
@testable import Merlin

final class PlannerEngineTests: XCTestCase {

    private let softwareDomain = SoftwareDomain()

    // MARK: - Classification

    func testClassifyRoutineTask() async {
        let engine = makePlanner(classifierResponse: """
            { "needs_planning": false, "complexity": "routine", "reason": "simple rename" }
            """)
        let result = await engine.classify(message: "rename this variable", domain: softwareDomain)
        XCTAssertFalse(result.needsPlanning)
        XCTAssertEqual(result.complexity, .routine)
    }

    func testClassifyStandardTask() async {
        let engine = makePlanner(classifierResponse: """
            { "needs_planning": true, "complexity": "standard", "reason": "multi-file refactor" }
            """)
        let result = await engine.classify(message: "refactor the auth module", domain: softwareDomain)
        XCTAssertTrue(result.needsPlanning)
        XCTAssertEqual(result.complexity, .standard)
    }

    func testClassifyHighStakesFromKeyword() async {
        let engine = makePlanner(classifierResponse: """
            { "needs_planning": true, "complexity": "high-stakes", "reason": "auth change" }
            """)
        let result = await engine.classify(message: "update authentication logic", domain: softwareDomain)
        XCTAssertEqual(result.complexity, .highStakes)
    }

    // MARK: - Tier override

    func testHighStakesTierOverrideAnnotation() async {
        let engine = makePlanner(classifierResponse: """
            { "needs_planning": true, "complexity": "routine", "reason": "would be routine" }
            """)
        let result = await engine.classify(
            message: "#high-stakes migrate the users table to add TOTP columns",
            domain: softwareDomain
        )
        // #high-stakes annotation overrides classifier output
        XCTAssertEqual(result.complexity, .highStakes)
    }

    func testRoutineTierOverrideAnnotation() async {
        let engine = makePlanner(classifierResponse: """
            { "needs_planning": false, "complexity": "high-stakes", "reason": "classifier over-estimates" }
            """)
        let result = await engine.classify(
            message: "#routine summarise this function",
            domain: softwareDomain
        )
        XCTAssertEqual(result.complexity, .routine)
    }

    // MARK: - Decomposition

    func testDecomposeReturnsSteps() async {
        let engine = makePlanner(plannerResponse: """
            {
                "steps": [
                    { "description": "Add migration file", "successCriteria": "File exists", "complexity": "standard" },
                    { "description": "Update model struct", "successCriteria": "Tests pass", "complexity": "standard" }
                ]
            }
            """)
        let steps = await engine.decompose(task: "add a new column to the users table", context: [])
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].description, "Add migration file")
        XCTAssertEqual(steps[1].description, "Update model struct")
    }

    func testDecomposeReturnsEmptyOnProviderFailure() async {
        let engine = PlannerEngine(
            executeProvider: FailingProvider(),
            orchestrateProvider: nil,
            maxPlanRetries: 2
        )
        let steps = await engine.decompose(task: "any task", context: [])
        XCTAssertTrue(steps.isEmpty)
    }
}

// MARK: - Helpers

private func makePlanner(
    classifierResponse: String = #"{"needs_planning":false,"complexity":"routine","reason":"simple"}"#,
    plannerResponse: String = #"{"steps":[]}"#
) -> PlannerEngine {
    PlannerEngine(
        executeProvider: ScriptedProvider(response: classifierResponse),
        orchestrateProvider: ScriptedProvider(response: plannerResponse),
        maxPlanRetries: 2
    )
}

private final class ScriptedProvider: LLMProvider {
    let id = "scripted"
    var response: String
    init(response: String) { self.response = response }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(
                delta: ChunkDelta(content: text, thinkingContent: nil, toolCalls: nil),
                finishReason: "stop"
            ))
            continuation.finish()
        }
    }
}

private final class FailingProvider: LLMProvider {
    let id = "failing"
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        throw URLError(.notConnectedToInternet)
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `ComplexityTier`, `ClassifierResult`, `PlannerEngine`, `PlanStep` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/PlannerEngineTests.swift
git commit -m "Phase 103a — PlannerEngineTests (failing)"
```
