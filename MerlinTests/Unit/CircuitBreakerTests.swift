import XCTest
@testable import Merlin

@MainActor
final class CircuitBreakerTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AppSettings.shared.agentCircuitBreakerThreshold = 3
        AppSettings.shared.agentCircuitBreakerMode = "halt"
    }

    // MARK: - Helpers

    private func makeEngine(
        threshold: Int,
        mode: String = "halt"
    ) -> AgenticEngine {
        AppSettings.shared.agentCircuitBreakerThreshold = threshold
        AppSettings.shared.agentCircuitBreakerMode = mode
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let engine = AgenticEngine(
            proProvider: MockProvider(responses: [.text("response")]),
            flashProvider: MockProvider(responses: [.text("response")]),
            visionProvider: LMStudioProvider(),
            toolRouter: router,
            contextManager: ContextManager()
        )
        engine.criticOverride = AlwaysFailCritic()
        engine.classifierOverride = StubClassifier()
        return engine
    }

    private func systemNotes(
        from engine: AgenticEngine,
        message: String = "test"
    ) async -> [String] {
        var notes: [String] = []
        for await event in engine.send(userMessage: message) {
            if case .systemNote(let note) = event {
                notes.append(note)
            }
        }
        return notes
    }

    private func textOutput(
        from engine: AgenticEngine,
        message: String = "test"
    ) async -> [String] {
        var texts: [String] = []
        for await event in engine.send(userMessage: message) {
            if case .text(let text) = event {
                texts.append(text)
            }
        }
        return texts
    }

    // MARK: - Counter

    func testCounterIncrementsOnConsecutiveFails() async throws {
        let engine = makeEngine(threshold: 10)
        XCTAssertEqual(engine.consecutiveCriticFailures, 0)
        for await _ in engine.send(userMessage: "t1") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 1)
        for await _ in engine.send(userMessage: "t2") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 2)
    }

    func testCounterResetsOnPass() async throws {
        let engine = makeEngine(threshold: 10)
        for await _ in engine.send(userMessage: "fail") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 1)
        engine.criticOverride = AlwaysPassCritic()
        for await _ in engine.send(userMessage: "pass") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 0)
    }

    func testCounterResetsOnSkipped() async throws {
        let engine = makeEngine(threshold: 10)
        for await _ in engine.send(userMessage: "fail") {}
        engine.criticOverride = AlwaysSkippedCritic()
        for await _ in engine.send(userMessage: "skip") {}
        XCTAssertEqual(engine.consecutiveCriticFailures, 0)
    }

    // MARK: - Warn mode

    func testWarnModeEmitsNoteAtThreshold() async throws {
        let engine = makeEngine(threshold: 2, mode: "warn")
        for await _ in engine.send(userMessage: "t1") {}
        let notes = await systemNotes(from: engine, message: "t2")
        let circuitNotes = notes.filter { $0.contains("Reliability") || $0.contains("quality") }
        XCTAssertFalse(circuitNotes.isEmpty)
    }

    func testWarnModeStillProducesTextAboveThreshold() async throws {
        let engine = makeEngine(threshold: 1, mode: "warn")
        for await _ in engine.send(userMessage: "trip") {}
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
        for _ in 0..<5 {
            allNotes += await systemNotes(from: engine)
        }
        XCTAssertTrue(allNotes.filter { $0.contains("Reliability") }.isEmpty)
    }

    // MARK: - Halt mode

    func testHaltModeProducesNoTextAfterThreshold() async throws {
        let engine = makeEngine(threshold: 2, mode: "halt")
        for await _ in engine.send(userMessage: "t1") {}
        for await _ in engine.send(userMessage: "t2") {}
        let texts = await textOutput(from: engine, message: "t3")
        XCTAssertTrue(texts.isEmpty, "Halt mode must suppress text when circuit is tripped")
    }

    func testHaltModeEmitsLabelledSystemNoteOnHalt() async throws {
        let engine = makeEngine(threshold: 2, mode: "halt")
        for await _ in engine.send(userMessage: "t1") {}
        for await _ in engine.send(userMessage: "t2") {}
        let notes = await systemNotes(from: engine, message: "t3")
        XCTAssertFalse(notes.isEmpty, "Halt must emit a systemNote explaining the halt")
        let haltNote = notes.first(where: {
            $0.contains("Halt") || $0.contains("halt") || $0.contains("stop") || $0.contains("Stop")
        })
        XCTAssertNotNil(haltNote, "Halt note should describe the stop condition")
    }

    func testHaltModeNoteIncludesFailureCount() async throws {
        let engine = makeEngine(threshold: 2, mode: "halt")
        for await _ in engine.send(userMessage: "t1") {}
        for await _ in engine.send(userMessage: "t2") {}
        let notes = await systemNotes(from: engine, message: "t3")
        let countMentioned = notes.contains { $0.contains("2") || $0.contains("two") }
        XCTAssertTrue(countMentioned, "Halt note should mention the failure count")
    }

    // MARK: - New session resets counter

    func testNewSessionResetsConsecutiveCriticFailures() async throws {
        let state = AppState(projectPath: "")
        let engine = state.engine!
        engine.consecutiveCriticFailures = 2
        state.newSession()
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

// MARK: - Test doubles

private struct AlwaysFailCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .fail(reason: "always fail")
    }
}

private struct AlwaysPassCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .pass
    }
}

private struct AlwaysSkippedCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .skipped
    }
}

private struct StubClassifier: PlannerEngineProtocol {
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        ClassifierResult(needsPlanning: false, complexity: .standard, reason: "stub")
    }

    func decompose(task: String, context: [Message]) async -> [PlanStep] { [] }
}
