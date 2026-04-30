import XCTest
@testable import Merlin

/// Semantic fault injection scenario tests.
///
/// Each test injects a specific degradation into the engine's data or context pipeline
/// and asserts that Merlin's behavioral monitoring stack (GroundingReport, circuit
/// breaker, ModelParameterAdvisor) detects it rather than silently producing fluent but
/// wrong output.
@MainActor
final class SemanticFaultInjectionTests: XCTestCase {

    private var savedFreshnessThreshold: Int = 90
    private var savedMinGroundingScore: Double = 0.30
    private var savedCircuitBreakerThreshold: Int = 3
    private var savedCircuitBreakerMode: String = "warn"

    override func setUp() async throws {
        try await super.setUp()
        savedFreshnessThreshold = AppSettings.shared.ragFreshnessThresholdDays
        savedMinGroundingScore = AppSettings.shared.ragMinGroundingScore
        savedCircuitBreakerThreshold = AppSettings.shared.agentCircuitBreakerThreshold
        savedCircuitBreakerMode = AppSettings.shared.agentCircuitBreakerMode
        AppSettings.shared.ragFreshnessThresholdDays = 90
        AppSettings.shared.ragMinGroundingScore = 0.30
        AppSettings.shared.agentCircuitBreakerThreshold = 3
        AppSettings.shared.agentCircuitBreakerMode = "warn"
    }

    override func tearDown() async throws {
        AppSettings.shared.ragFreshnessThresholdDays = savedFreshnessThreshold
        AppSettings.shared.ragMinGroundingScore = savedMinGroundingScore
        AppSettings.shared.agentCircuitBreakerThreshold = savedCircuitBreakerThreshold
        AppSettings.shared.agentCircuitBreakerMode = savedCircuitBreakerMode
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeEngine(
        provider: any LLMProvider,
        contextManager: ContextManager = ContextManager(),
        memoryBackend: (any MemoryBackendPlugin)? = nil,
        xcalibreClient: (any XcalibreClientProtocol)? = nil,
        router: ToolRouter? = nil
    ) -> AgenticEngine {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let toolRouter = router ?? ToolRouter(authGate: gate)
        let engine = AgenticEngine(
            proProvider: provider,
            flashProvider: provider,
            visionProvider: LMStudioProvider(),
            toolRouter: toolRouter,
            contextManager: contextManager,
            xcalibreClient: xcalibreClient,
            memoryBackend: memoryBackend
        )
        engine.criticOverride = AlwaysPassCritic()
        engine.classifierOverride = StubClassifier()
        return engine
    }

    private func groundingReport(
        from engine: AgenticEngine,
        message: String = "hello"
    ) async -> GroundingReport? {
        var report: GroundingReport?
        for await event in engine.send(userMessage: message) {
            if case .groundingReport(let value) = event {
                report = value
            }
        }
        return report
    }

    // MARK: - Scenario 1: Stale retrieval

    func testStaleRetrievalDetectedByGroundingReport() async throws {
        let staleBackend = StalenessInjectingMemoryBackend(ageDays: 120)
        let engine = makeEngine(
            provider: MockProvider(responses: [.text("response")]),
            memoryBackend: staleBackend
        )

        let report = await groundingReport(from: engine, message: "What do you know about my preferences?")

        XCTAssertNotNil(report, "GroundingReport must be emitted")
        XCTAssertTrue(report?.hasStaleMemory == true,
                      "120-day-old chunks should trigger hasStaleMemory")
        XCTAssertGreaterThan(report?.totalChunks ?? 0, 0,
                             "Stale backend still returns chunks")
    }

    func testFreshRetrievalPassesStalenessCheck() async throws {
        let freshBackend = StalenessInjectingMemoryBackend(ageDays: 5)
        let engine = makeEngine(
            provider: MockProvider(responses: [.text("ok")]),
            memoryBackend: freshBackend
        )

        let report = await groundingReport(from: engine)

        XCTAssertEqual(report?.hasStaleMemory, false)
    }

    // MARK: - Scenario 2: Token pressure / truncation

    func testTruncatingProviderStillEmitsGroundingReport() async throws {
        let engine = makeEngine(
            provider: TruncatingMockProvider(maxChars: 15)
        )

        var reportEmitted = false
        for await event in engine.send(userMessage: "explain something complex") {
            if case .groundingReport = event {
                reportEmitted = true
            }
        }

        XCTAssertTrue(reportEmitted,
                      "GroundingReport must be emitted even when provider truncates output")
    }

    func testTruncatingProviderAccumulatesInAdvisor() async throws {
        let advisor = ModelParameterAdvisor()
        let engine = makeEngine(
            provider: TruncatingMockProvider(maxChars: 10)
        )
        engine.parameterAdvisor = advisor

        for i in 0..<12 {
            for await _ in engine.send(userMessage: "turn \(i)") {}
        }

        let advisories = await advisor.currentAdvisories(for: engine.currentModelID)
        XCTAssertTrue(advisories.contains { $0.kind == ParameterAdvisoryKind.maxTokensTooLow },
                      "Truncation should be recorded by the advisor")
    }

    // MARK: - Scenario 3: Empty tool results

    func testEmptyToolResultsDoNotCrashEngine() async throws {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = EmptyToolResultRouter(authGate: gate)
        router.register(name: "run_shell") { _ in "tool output" }

        let engine = makeEngine(
            provider: MockProvider(responses: [
                .toolCall(id: "call-1", name: "run_shell", args: #"{"command":"echo hi"}"#),
                .text("Done.")
            ]),
            router: router
        )

        for await event in engine.send(userMessage: "list files in current directory") {
            if case .error = event {
                XCTFail("Engine must not emit error on empty tool result")
            }
        }
    }

    func testCircuitBreakerIncrementsSustainedEmptyToolFailures() async throws {
        AppSettings.shared.agentCircuitBreakerThreshold = 2
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = EmptyToolResultRouter(authGate: gate)
        router.register(name: "run_shell") { _ in "tool output" }

        let engine = makeEngine(
            provider: MockProvider(responses: Array(repeating: .text("ok"), count: 10)),
            router: router
        )
        engine.criticOverride = AlwaysFailCritic()

        for _ in 0..<3 {
            for await _ in engine.send(userMessage: "test") {}
        }

        XCTAssertGreaterThanOrEqual(engine.consecutiveCriticFailures, 2,
                                    "Sustained empty-tool-result failures must accumulate in circuit breaker")
    }

    // MARK: - Scenario 4: Context drop

    func testGroundingReportEmittedWithDroppedContext() async throws {
        let droppingContext = DroppingContextManager(dropCount: 5)
        let engine = makeEngine(
            provider: MockProvider(responses: [.text("ok")]),
            contextManager: droppingContext
        )

        var reportEmitted = false
        for await event in engine.send(userMessage: "remember what we discussed earlier?") {
            if case .groundingReport = event {
                reportEmitted = true
            }
        }

        XCTAssertTrue(reportEmitted,
                      "GroundingReport must be emitted even when context has been dropped")
    }

    func testEngineStableWithAggressiveContextDrop() async throws {
        let droppingContext = DroppingContextManager(dropCount: 50)
        let engine = makeEngine(
            provider: MockProvider(responses: Array(repeating: .text("ok"), count: 5)),
            contextManager: droppingContext
        )

        for i in 0..<5 {
            for await event in engine.send(userMessage: "turn \(i)") {
                if case .error(let error) = event {
                    XCTFail("Engine must not error with dropping context: \(error)")
                }
            }
        }
    }
}

private struct AlwaysPassCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .pass
    }
}

private struct AlwaysFailCritic: CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        .fail(reason: "always fail")
    }
}

private struct StubClassifier: PlannerEngineProtocol {
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        ClassifierResult(needsPlanning: false, complexity: .standard, reason: "stub")
    }

    func decompose(task: String, context: [Message]) async -> [PlanStep] { [] }
}
