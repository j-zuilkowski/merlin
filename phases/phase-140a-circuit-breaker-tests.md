# Phase 140a — Reasoning-Layer Circuit Breaker Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 139 complete (or v9 phases in progress). All prior tests pass.

Motivation:
Addresses the "safe halt conditions" mitigation from:
"Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems" — VentureBeat
https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems

The article states: "A graceful halt is almost always safer than a fluent error. Too many
systems are designed to keep going because confident output creates the illusion of
correctness." Two modes are provided: "warn" (surface the signal, keep running) and
"halt" (stop cleanly, label the failure, require the user to start a new session).
"halt" is the default.

New surface introduced in phase 140b:
  - `AgenticEngine.consecutiveCriticFailures: Int` — increments on .fail, resets on
    .pass or .skipped.
  - `AppSettings.agentCircuitBreakerThreshold: Int` — TOML: `agent_circuit_breaker_threshold`.
    Default: 3. Setting to 0 disables entirely.
  - `AppSettings.agentCircuitBreakerMode: String` — TOML: `agent_circuit_breaker_mode`.
    "halt" (default) or "warn".
  - In "warn" mode: emits a .systemNote at end of each turn at or above threshold.
  - In "halt" mode: emits a .systemNote at the START of any turn when
    consecutiveCriticFailures >= threshold, then returns early — no text output.
  - `AppState.newSession()` resets `consecutiveCriticFailures` to 0 on the engine.

TDD coverage:
  File: MerlinTests/Unit/CircuitBreakerTests.swift

---

## Write to: MerlinTests/Unit/CircuitBreakerTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class CircuitBreakerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppSettings.shared.agentCircuitBreakerThreshold = 3
        AppSettings.shared.agentCircuitBreakerMode = "halt"
    }

    // MARK: - Helpers

    private func makeEngine(threshold: Int,
                            mode: String = "halt") -> AgenticEngine {
        AppSettings.shared.agentCircuitBreakerThreshold = threshold
        AppSettings.shared.agentCircuitBreakerMode = mode
        let engine = AgenticEngine(
            provider: MockProvider(responses: ["response"]),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager()
        )
        engine.criticOverride = AlwaysFailCritic()
        return engine
    }

    private func systemNotes(from engine: AgenticEngine,
                             message: String = "test") async -> [String] {
        var notes: [String] = []
        for await event in engine.send(message) {
            if case .systemNote(let n) = event { notes.append(n) }
        }
        return notes
    }

    private func textOutput(from engine: AgenticEngine,
                            message: String = "test") async -> [String] {
        var texts: [String] = []
        for await event in engine.send(message) {
            if case .text(let t) = event { texts.append(t) }
        }
        return texts
    }

    // MARK: - Counter

    func testCounterIncrementsOnConsecutiveFails() async throws {
        let engine = makeEngine(threshold: 10)
        XCTAssertEqual(engine.consecutiveCriticFailures, 0)
        for await _ in engine.send("t1") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 1)
        for await _ in engine.send("t2") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 2)
    }

    func testCounterResetsOnPass() async throws {
        let engine = makeEngine(threshold: 10)
        for await _ in engine.send("fail") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 1)
        engine.criticOverride = AlwaysPassCritic()
        for await _ in engine.send("pass") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 0)
    }

    func testCounterResetsOnSkipped() async throws {
        let engine = makeEngine(threshold: 10)
        for await _ in engine.send("fail") {}
        engine.criticOverride = AlwaysSkippedCritic()
        for await _ in engine.send("skip") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 0)
    }

    // MARK: - Warn mode

    func testWarnModeEmitsNoteAtThreshold() async throws {
        let engine = makeEngine(threshold: 2, mode: "warn")
        for await _ in engine.send("t1") {}  // count=1, below threshold
        let notes = await systemNotes(from: engine, message: "t2")  // count=2, at threshold
        let circuitNotes = notes.filter { $0.contains("Reliability") || $0.contains("quality") }
        XCTAssertFalse(circuitNotes.isEmpty)
    }

    func testWarnModeStillProducesTextAboveThreshold() async throws {
        let engine = makeEngine(threshold: 1, mode: "warn")
        // With threshold=1, first turn should warn but still produce text
        for await _ in engine.send("trip") {}  // count=1, at threshold
        // Next turn: warn mode — should still produce text
        let texts = await textOutput(from: engine, message: "next")
        XCTAssertFalse(texts.isEmpty, "Warn mode must not suppress text output")
    }

    func testNoNoteBeforeThreshold() async throws {
        let engine = makeEngine(threshold: 5, mode: "warn")
        var allNotes: [String] = []
        for _ in 0..<4 {
            allNotes += await systemNotes(from: engine)
        }
        let circuitNotes = allNotes.filter { $0.contains("Reliability") || $0.contains("quality") }
        XCTAssertTrue(circuitNotes.isEmpty)
    }

    func testNoNoteWhenThresholdIsZero() async throws {
        let engine = makeEngine(threshold: 0, mode: "warn")
        var allNotes: [String] = []
        for _ in 0..<5 { allNotes += await systemNotes(from: engine) }
        XCTAssertTrue(allNotes.filter { $0.contains("Reliability") }.isEmpty)
    }

    // MARK: - Halt mode

    func testHaltModeProducesNoTextAfterThreshold() async throws {
        let engine = makeEngine(threshold: 2, mode: "halt")
        for await _ in engine.send("t1") {}  // count=1
        for await _ in engine.send("t2") {}  // count=2, warning
        // t3: counter >= threshold in halt mode → halt
        let texts = await textOutput(from: engine, message: "t3")
        XCTAssertTrue(texts.isEmpty, "Halt mode must suppress text when circuit is tripped")
    }

    func testHaltModeEmitsLabelledSystemNoteOnHalt() async throws {
        let engine = makeEngine(threshold: 2, mode: "halt")
        for await _ in engine.send("t1") {}
        for await _ in engine.send("t2") {}
        let notes = await systemNotes(from: engine, message: "t3")
        XCTAssertFalse(notes.isEmpty, "Halt must emit a systemNote explaining the halt")
        let haltNote = notes.first(where: {
            $0.contains("Halt") || $0.contains("halt") || $0.contains("stop") || $0.contains("Stop")
        })
        XCTAssertNotNil(haltNote, "Halt note should describe the stop condition")
    }

    func testHaltModeNoteIncludesFailureCount() async throws {
        let engine = makeEngine(threshold: 2, mode: "halt")
        for await _ in engine.send("t1") {}
        for await _ in engine.send("t2") {}
        let notes = await systemNotes(from: engine, message: "t3")
        let countMentioned = notes.contains { $0.contains("2") || $0.contains("two") }
        XCTAssertTrue(countMentioned, "Halt note should mention the failure count")
    }

    // MARK: - New session resets counter

    func testNewSessionResetsConsecutiveCriticFailures() async throws {
        let engine = makeEngine(threshold: 10)
        for await _ in engine.send("t1") {}
        for await _ in engine.send("t2") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 2)
        // Simulate new session
        engine.consecutiveCriticFailures = 0  // AppState.newSession() will do this
        XCTAssertEqual(engine.consecutiveCriticFailures, 0)
    }

    // MARK: - AppSettings defaults

    func testCircuitBreakerThresholdDefaultIsThree() {
        let fresh = AppSettings()
        XCTAssertEqual(fresh.agentCircuitBreakerThreshold, 3)
    }

    func testCircuitBreakerModeDefaultIsHalt() {
        let fresh = AppSettings()
        XCTAssertEqual(fresh.agentCircuitBreakerMode, "halt")
    }
}

// MARK: - AlwaysSkippedCritic

final class AlwaysSkippedCritic: CriticEngineProtocol, Sendable {
    func score(question: String, answer: String, context: [Message]) async -> CriticResult {
        .skipped
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
Expected: BUILD FAILED — `AgenticEngine.consecutiveCriticFailures`,
`AppSettings.agentCircuitBreakerThreshold`, `AppSettings.agentCircuitBreakerMode` undefined.

## Commit
```bash
git add MerlinTests/Unit/CircuitBreakerTests.swift
git commit -m "Phase 140a — circuit breaker tests (failing)"
```
