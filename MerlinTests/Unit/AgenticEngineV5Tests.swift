import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineV5Tests: XCTestCase {

    // MARK: - Complexity tier routing

    func testRoutineTaskSkipsCritic() async {
        let (engine, criticSpy) = makeEngineWithCriticSpy(classifierTier: .routine)
        _ = await collectEvents(engine.send(userMessage: "rename this variable"))
        XCTAssertFalse(criticSpy.wasEvaluated, "Routine tasks should skip the critic")
    }

    func testStandardTaskRunsCritic() async {
        let (engine, criticSpy) = makeEngineWithCriticSpy(classifierTier: .standard)
        _ = await collectEvents(engine.send(userMessage: "refactor the auth module"))
        XCTAssertTrue(criticSpy.wasEvaluated, "Standard tasks should run the critic")
    }

    func testHighStakesUsesReasonSlot() async {
        let providerSpy = ProviderCallSpy()
        let engine = makeEngine(
            executeProvider: ScriptedProvider(id: "execute", response: "done"),
            reasonProvider: providerSpy
        )
        _ = await collectEvents(engine.send(userMessage: "#high-stakes migrate users table"))
        XCTAssertTrue(providerSpy.wasCalled, "High-stakes tasks should invoke the reason slot provider")
    }

    // MARK: - RAG source parameter

    func testRAGSearchUsesSourceAll() async {
        let clientSpy = XcalibreClientSpy()
        let engine = makeEngine(xcalibreClient: clientSpy)
        _ = await collectEvents(engine.send(userMessage: "how does auth work?"))
        XCTAssertEqual(clientSpy.lastSearchSource, "all",
                       "RAG search should use source=all to include memory chunks")
    }

    func testRAGSearchPassesProjectPath() async {
        let clientSpy = XcalibreClientSpy()
        let engine = makeEngine(xcalibreClient: clientSpy)
        engine.currentProjectPath = "/Users/jon/project"
        _ = await collectEvents(engine.send(userMessage: "explain this"))
        XCTAssertEqual(clientSpy.lastSearchProjectPath, "/Users/jon/project")
    }

    // MARK: - Outcome recording

    func testOutcomeRecordedAtSessionEnd() async {
        let trackerSpy = PerformanceTrackerSpy()
        let engine = makeEngine(tracker: trackerSpy)
        _ = await collectEvents(engine.send(userMessage: "write tests for the auth module"))
        XCTAssertTrue(trackerSpy.recordCalled, "Outcome should be recorded at session end")
    }

    // MARK: - Unverified badge

    func testUnverifiedEventEmittedWhenCriticSkipped() async {
        let (engine, _) = makeEngineWithCriticSpy(
            classifierTier: .standard,
            reasonProviderAvailable: false
        )
        let events = await collectEvents(engine.send(userMessage: "refactor auth"))
        let hasUnverified = events.contains {
            if case .systemNote(let note) = $0 { return note.contains("unverified") }
            return false
        }
        XCTAssertTrue(hasUnverified, "Should emit unverified note when critic is skipped")
    }
}

// MARK: - Helpers

private func collectEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

@MainActor
private func makeEngine(
    executeProvider: any LLMProvider = ScriptedProvider(id: "execute", response: "done"),
    reasonProvider: (any LLMProvider)? = nil,
    xcalibreClient: (any XcalibreClientProtocol)? = nil,
    tracker: (any ModelPerformanceTrackerProtocol)? = nil
) -> AgenticEngine {
    let registry = ProviderRegistry()
    registry.add(executeProvider)
    if let rp = reasonProvider { registry.add(rp) }

    var slots: [AgentSlot: String] = [.execute: executeProvider.id]
    if let rp = reasonProvider { slots[.reason] = rp.id }

    let gate = AuthGate(
        memory: AuthMemory(storePath: "/tmp/auth-agenticengine-v5-tests.json"),
        presenter: NullAuthPresenter()
    )

    let engine = AgenticEngine(
        slotAssignments: slots,
        registry: registry,
        toolRouter: ToolRouter(authGate: gate),
        contextManager: ContextManager(),
        xcalibreClient: xcalibreClient
    )
    if let t = tracker { engine.performanceTracker = t }
    return engine
}

@MainActor
private func makeEngineWithCriticSpy(
    classifierTier: ComplexityTier,
    reasonProviderAvailable: Bool = true
) -> (AgenticEngine, CriticSpy) {
    let spy = CriticSpy()
    let reason: (any LLMProvider)? = reasonProviderAvailable
        ? ScriptedProvider(id: "reason", response: "PASS: looks good") : nil
    let engine = makeEngine(reasonProvider: reason)
    engine.criticOverride = spy
    engine.classifierOverride = FixedClassifier(tier: classifierTier)
    return (engine, spy)
}

private final class ScriptedProvider: LLMProvider {
    let id: String
    let response: String
    init(id: String, response: String) { self.id = id; self.response = response }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: text, toolCalls: nil, thinkingContent: nil), finishReason: "stop"))
            c.finish()
        }
    }
}

@MainActor
private final class ProviderCallSpy: LLMProvider {
    let id = "spy-reason"
    var wasCalled = false
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        wasCalled = true
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: "done", toolCalls: nil, thinkingContent: nil), finishReason: "stop"))
            c.finish()
        }
    }
}

private final class XcalibreClientSpy: @unchecked Sendable, XcalibreClientProtocol {
    nonisolated(unsafe) var lastSearchSource: String?
    nonisolated(unsafe) var lastSearchProjectPath: String?
    func probe() async {}
    func isAvailable() async -> Bool { true }
    func searchChunks(query: String, source: String, bookIDs: [String]?, projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk] {
        lastSearchSource = source
        lastSearchProjectPath = projectPath
        return []
    }
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?, projectPath: String?, tags: [String]) async -> String? { nil }
    func deleteMemoryChunk(id: String) async {}
    func listBooks(limit: Int) async -> [RAGBook] { [] }
}

private final class PerformanceTrackerSpy: @unchecked Sendable, ModelPerformanceTrackerProtocol {
    nonisolated(unsafe) var recordCalled = false
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async { recordCalled = true }
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double? { nil }
    func profile(for modelID: String) -> [ModelPerformanceProfile] { [] }
    func allProfiles() -> [ModelPerformanceProfile] { [] }
}

private final class CriticSpy: @unchecked Sendable, CriticEngineProtocol {
    nonisolated(unsafe) var wasEvaluated = false
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        wasEvaluated = true
        return .pass
    }
}

private struct FixedClassifier: PlannerEngineProtocol {
    var tier: ComplexityTier
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        ClassifierResult(needsPlanning: tier != .routine, complexity: tier, reason: "fixed")
    }
    func decompose(task: String, context: [Message]) async -> [PlanStep] { [] }
}
