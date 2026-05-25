import XCTest
@testable import Merlin

// Tests for Task 164 — Critic retry loop + OutcomeSignals wiring
//
// Covers:
//   - AppSettings.criticEnabled default is true
//   - AppSettings.maxCriticRetries default is 2
//   - Engine retries after critic fail (injects correction message, re-runs worker)
//   - Engine stops after maxCriticRetries exhausted and emits escalation note
//   - OutcomeSignals.criticRetryCount == actual retry count
//   - OutcomeSignals.stage1Passed true on pass, false when retries exhausted, nil on skipped
//   - When criticEnabled = false, critic is never called even on substantial output

@MainActor
final class AgenticEngineCriticRetryTests: XCTestCase {

    // MARK: - AppSettings defaults

    func testCriticEnabledDefaultIsTrue() {
        let settings = AppSettings()
        XCTAssertTrue(settings.criticEnabled,
                      "criticEnabled must default to true")
    }

    func testMaxCriticRetriesDefaultIsTwo() {
        let settings = AppSettings()
        XCTAssertEqual(settings.maxCriticRetries, 2,
                       "maxCriticRetries must default to 2")
    }

    // MARK: - Retry count

    func testEngineCallsCriticOnceWhenPassOnFirstTry() async {
        let spy = RetryCountCriticSpy(failTimes: 0)
        let engine = makeCriticRetryEngine(spy: spy)
        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        XCTAssertEqual(spy.evaluateCallCount, 1,
                       "Critic should be called exactly once when it passes immediately")
    }

    func testEngineRetryOnceAfterOneFail() async {
        let spy = RetryCountCriticSpy(failTimes: 1)
        let engine = makeCriticRetryEngine(spy: spy)
        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        // Initial evaluation (fail) + 1 retry (pass) = 2 total
        XCTAssertEqual(spy.evaluateCallCount, 2,
                       "Critic should be called initial + 1 retry, got \(spy.evaluateCallCount)")
    }

    func testCriticCallCountStopsAtMaxRetriesPlusOne() async {
        let settings = AppSettings.shared
        let originalRetries = settings.maxCriticRetries
        settings.maxCriticRetries = 2
        defer { settings.maxCriticRetries = originalRetries }

        // Always fail — will hit ceiling
        let spy = RetryCountCriticSpy(failTimes: 99)
        let engine = makeCriticRetryEngine(spy: spy)
        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        // 1 initial + 2 retries = 3 calls max
        XCTAssertEqual(spy.evaluateCallCount, 3,
                       "With maxCriticRetries=2, critic evaluates at most 3 times (initial + 2 retries)")
    }

    // MARK: - Correction injection

    func testCorrectionMessageInjectedIntoContextOnRetry() async {
        let spy = RetryCountCriticSpy(failTimes: 1)
        let engine = makeCriticRetryEngine(spy: spy)
        _ = await collectEvents(engine.send(userMessage: "implement the module"))

        // On the second (retry) evaluate call, the context must contain a correction message
        // that references the critic's failure reason
        guard let retryContext = spy.contextOnSecondCall else {
            XCTFail("Spy did not capture context on retry call")
            return
        }
        let hasCorrectionEntry = retryContext.contains { msg in
            switch msg.content {
            case .text(let t):
                return t.contains("Critic") || t.contains("correction") || t.contains("retry")
            default:
                return false
            }
        }
        XCTAssertTrue(hasCorrectionEntry,
                      "Context on retry must contain a critic correction injection message")
    }

    // MARK: - Escalation note after exhaustion

    func testEscalationNoteEmittedAfterRetriesExhausted() async {
        let settings = AppSettings.shared
        let originalRetries = settings.maxCriticRetries
        settings.maxCriticRetries = 1
        defer { settings.maxCriticRetries = originalRetries }

        let spy = RetryCountCriticSpy(failTimes: 99) // always fail
        let engine = makeCriticRetryEngine(spy: spy)
        let events = await collectEvents(engine.send(userMessage: "implement the module"))

        let escalationNotes = events.compactMap { event -> String? in
            if case .systemNote(let text) = event { return text }
            return nil
        }.filter { note in
            note.lowercased().contains("exhaust") ||
            note.lowercased().contains("max") ||
            (note.lowercased().contains("critic") && note.lowercased().contains("retr"))
        }
        XCTAssertFalse(escalationNotes.isEmpty,
                       "Engine must emit an escalation system note after retries are exhausted")
    }

    // MARK: - OutcomeSignals wiring

    func testOutcomeSignalsCriticRetryCountZeroOnFirstPassAttempt() async throws {
        try skipUnlessLiveEnvironment()
        let spy = RetryCountCriticSpy(failTimes: 0)
        let tracker = CapturingPerformanceTracker()
        let engine = makeCriticRetryEngine(spy: spy)
        engine.performanceTracker = tracker

        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        XCTAssertEqual(tracker.lastSignals?.criticRetryCount, 0,
                       "criticRetryCount must be 0 when critic passes on first attempt")
    }

    func testOutcomeSignalsCriticRetryCountOneAfterOneRetry() async throws {
        try skipUnlessLiveEnvironment()
        let settings = AppSettings.shared
        let originalRetries = settings.maxCriticRetries
        settings.maxCriticRetries = 2
        defer { settings.maxCriticRetries = originalRetries }

        let spy = RetryCountCriticSpy(failTimes: 1) // fail once, then pass
        let tracker = CapturingPerformanceTracker()
        let engine = makeCriticRetryEngine(spy: spy)
        engine.performanceTracker = tracker

        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        XCTAssertEqual(tracker.lastSignals?.criticRetryCount, 1,
                       "criticRetryCount must equal 1 after one retry")
    }

    func testOutcomeSignalsStage1PassedTrueWhenCriticPasses() async throws {
        try skipUnlessLiveEnvironment()
        let spy = RetryCountCriticSpy(failTimes: 0)
        let tracker = CapturingPerformanceTracker()
        let engine = makeCriticRetryEngine(spy: spy)
        engine.performanceTracker = tracker

        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        XCTAssertEqual(tracker.lastSignals?.stage1Passed, true,
                       "stage1Passed must be true when critic passes")
    }

    func testOutcomeSignalsStage1PassedFalseWhenAllRetriesExhausted() async throws {
        try skipUnlessLiveEnvironment()
        let settings = AppSettings.shared
        let originalRetries = settings.maxCriticRetries
        settings.maxCriticRetries = 1
        defer { settings.maxCriticRetries = originalRetries }

        let spy = RetryCountCriticSpy(failTimes: 99)
        let tracker = CapturingPerformanceTracker()
        let engine = makeCriticRetryEngine(spy: spy)
        engine.performanceTracker = tracker

        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        XCTAssertEqual(tracker.lastSignals?.stage1Passed, false,
                       "stage1Passed must be false when critic fails through all retries")
    }

    func testOutcomeSignalsStage1PassedNilWhenCriticSkipped() async {
        let spy = SkippedCriticSpy()
        let tracker = CapturingPerformanceTracker()
        let engine = makeCriticRetryEngine(spy: spy)
        engine.performanceTracker = tracker

        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        XCTAssertNil(tracker.lastSignals?.stage1Passed,
                     "stage1Passed must be nil when critic returns .skipped")
    }

    // MARK: - criticEnabled = false guard

    func testCriticDisabledSkipsEvaluationEntirely() async {
        let settings = AppSettings.shared
        let originalEnabled = settings.criticEnabled
        settings.criticEnabled = false
        defer { settings.criticEnabled = originalEnabled }

        let spy = RetryCountCriticSpy(failTimes: 0)
        let engine = makeCriticRetryEngine(spy: spy)
        _ = await collectEvents(engine.send(userMessage: "implement the module"))
        XCTAssertEqual(spy.evaluateCallCount, 0,
                       "Critic must not be called when criticEnabled = false")
    }
}

// MARK: - Helpers

@MainActor
private func makeCriticRetryEngine(spy: any CriticEngineProtocol) -> AgenticEngine {
    // LongTextProvider returns >1500 chars so isSubstantialOutput triggers the critic
    let executeProvider = LongTextProvider(id: "execute-retry-\(UUID().uuidString)")
    let registry = ProviderRegistry()
    registry.add(executeProvider)

    let gate = AuthGate(
        memory: AuthMemory(storePath: "/tmp/auth-critic-retry-\(UUID().uuidString).json"),
        presenter: NullAuthPresenter()
    )
    let engine = AgenticEngine(
        slotAssignments: [.execute: executeProvider.id],
        registry: registry,
        toolRouter: ToolRouter(authGate: gate),
        contextManager: ContextManager()
    )
    engine.criticOverride = spy
    return engine
}

private func collectEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

// MARK: - Test doubles

/// Provider that returns >1500 chars of plain text on every call, ensuring
/// `isSubstantialOutput` is true so the critic fires unconditionally.
private final class LongTextProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")

    init(id: String) { self.id = id }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        // 30 × 54 chars = 1620 chars — always above the 1500-char isSubstantialOutput threshold
        let longText = String(repeating: "This is a long response that will trigger the critic. ", count: 30)
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: longText, toolCalls: nil, thinkingContent: nil),
                finishReason: "stop"
            ))
            c.finish()
        }
    }
}

/// Critic spy that returns `.fail(reason:)` for the first `failTimes` calls,
/// then `.pass` for all subsequent calls. Tracks total call count and
/// captures the context passed on the second call (the retry).
final class RetryCountCriticSpy: @unchecked Sendable, CriticEngineProtocol {
    private let failTimes: Int
    nonisolated(unsafe) var evaluateCallCount = 0
    /// Context passed on the second evaluate call (i.e., the first retry).
    nonisolated(unsafe) var contextOnSecondCall: [Message]?

    init(failTimes: Int) { self.failTimes = failTimes }

    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message]
    ) async -> CriticResult {
        evaluateCallCount += 1
        if evaluateCallCount == 2 {
            contextOnSecondCall = context
        }
        return evaluateCallCount <= failTimes
            ? .fail(reason: "test-failure-attempt-\(evaluateCallCount)")
            : .pass
    }
}

/// Critic spy that always returns `.skipped`, for testing nil stage1Passed.
final class SkippedCriticSpy: @unchecked Sendable, CriticEngineProtocol {
    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message]
    ) async -> CriticResult {
        return .skipped
    }
}

/// Performance tracker that captures the most recently recorded OutcomeSignals.
final class CapturingPerformanceTracker: @unchecked Sendable, ModelPerformanceTrackerProtocol {
    var lastSignals: OutcomeSignals?

    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async {
        lastSignals = signals
    }

    func successRate(for modelID: String, taskType: DomainTaskType) -> Double? { nil }
    func profile(for modelID: String) -> [ModelPerformanceProfile] { [] }
    func allProfiles() -> [ModelPerformanceProfile] { [] }
    func records(for modelID: String, taskType: DomainTaskType) async -> [OutcomeRecord] { [] }
    func exportTrainingData(minScore: Double) async -> [OutcomeRecord] { [] }
}
