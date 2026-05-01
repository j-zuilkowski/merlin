import XCTest
@testable import Merlin

// MARK: - Local test doubles

/// Spy XcalibreClient: records every writeMemoryChunk call.
private final class SpyXcalibreClient: XcalibreClientProtocol, @unchecked Sendable {
    var writeCallCount = 0

    func probe() async {}
    func isAvailable() async -> Bool { true }
    func searchChunks(query: String, source: String, bookIDs: [String]?,
                      projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk] { [] }
    func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk] { [] }
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?,
                          projectPath: String?, tags: [String]) async -> String? {
        writeCallCount += 1
        return "mem-\(writeCallCount)"
    }
    func deleteMemoryChunk(id: String) async {}
    func listBooks(limit: Int) async -> [RAGBook] { [] }
}

/// Stub CriticEngine: always returns the configured verdict.
private struct StubCriticEngine: CriticEngineProtocol {
    let verdict: CriticResult
    func evaluate(taskType: DomainTaskType,
                  output: String,
                  context: [Message]) async -> CriticResult { verdict }
}

/// Stub Classifier / PlannerEngine: returns a fixed ClassifierResult.
private struct StubClassifier: PlannerEngineProtocol {
    let complexity: ComplexityTier
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        ClassifierResult(needsPlanning: false, complexity: complexity, reason: "stub")
    }
    func decompose(task: String, context: [Message]) async -> [PlanStep] { [] }
}

// MARK: - Helpers

@MainActor
private func makeTestEngine(
    spy: SpyXcalibreClient,
    memoryBackend: SpyMemoryBackend? = nil,
    executeResponse: String = "The answer is 42.",
    criticVerdict: CriticResult = .pass,
    classifierComplexity: ComplexityTier = .standard
) -> AgenticEngine {
    let provider = MockProvider()
    provider.stubbedResponse = executeResponse
    let engine = makeEngine(
        provider: provider,
        xcalibreClient: spy
    )
    if let mb = memoryBackend {
        engine.memoryBackend = mb
    }
    engine.criticOverride = StubCriticEngine(verdict: criticVerdict)
    // Non-routine complexity + classifierOverride != nil → critic branch entered
    engine.classifierOverride = StubClassifier(complexity: classifierComplexity)
    return engine
}

/// Seed an assistant message so the memory-write summary is non-empty.
@MainActor
private func seedAssistantMessage(_ engine: AgenticEngine) {
    engine.contextManager.append(
        Message(role: .assistant,
                content: .text("Earlier I helped you refactor the login flow."),
                timestamp: Date(timeIntervalSince1970: 0))
    )
}

/// Consume the stream returned by engine.send() and throw on .error events.
@MainActor
private func runEngine(_ engine: AgenticEngine, message: String = "help me") async throws {
    for await event in engine.send(userMessage: message) {
        if case .error(let err) = event { throw err }
    }
}

// MARK: - Tests

@MainActor
final class CriticGatedMemoryTests: XCTestCase {

    private var savedMemoriesEnabled = false

    override func setUp() async throws {
        savedMemoriesEnabled = AppSettings.shared.memoriesEnabled
        AppSettings.shared.memoriesEnabled = true
    }

    override func tearDown() async throws {
        AppSettings.shared.memoriesEnabled = savedMemoriesEnabled
    }

    // MARK: - lastCriticVerdict property exists on AgenticEngine

    func testLastCriticVerdictNilAtInit() {
        let spy = SpyXcalibreClient()
        let engine = makeTestEngine(spy: spy)
        // Phase 115b adds this property. Until then, BUILD FAILED.
        XCTAssertNil(engine.lastCriticVerdict)
    }

    // MARK: - Verdict stored after critic runs

    func testLastCriticVerdictStoredAsFailAfterFailingCritic() async throws {
        let spy = SpyXcalibreClient()
        let engine = makeTestEngine(spy: spy, criticVerdict: .fail(reason: "output was wrong"))
        seedAssistantMessage(engine)

        try await runEngine(engine)

        if case .fail(let reason) = engine.lastCriticVerdict {
            XCTAssertEqual(reason, "output was wrong")
        } else {
            XCTFail("Expected lastCriticVerdict == .fail(\"output was wrong\"), got \(String(describing: engine.lastCriticVerdict))")
        }
    }

    func testLastCriticVerdictStoredAsPassAfterPassingCritic() async throws {
        let spy = SpyXcalibreClient()
        let engine = makeTestEngine(spy: spy, criticVerdict: .pass)
        seedAssistantMessage(engine)

        try await runEngine(engine)

        XCTAssertEqual(engine.lastCriticVerdict, .pass)
    }

    // MARK: - Memory write gating

    func testMemoryNotWrittenWhenCriticFails() async throws {
        let spy = SpyXcalibreClient()
        let memSpy = SpyMemoryBackend()
        let engine = makeTestEngine(spy: spy, memoryBackend: memSpy, criticVerdict: .fail(reason: "wrong"))
        seedAssistantMessage(engine)

        try await runEngine(engine)

        let count = await memSpy.writeCallCount
        XCTAssertEqual(count, 0,
                       "Memory write must be suppressed when critic verdict is .fail")
    }

    func testMemoryWrittenWhenCriticPasses() async throws {
        let spy = SpyXcalibreClient()
        let memSpy = SpyMemoryBackend()
        let engine = makeTestEngine(spy: spy, memoryBackend: memSpy, criticVerdict: .pass)
        seedAssistantMessage(engine)

        try await runEngine(engine)

        let count = await memSpy.writeCallCount
        XCTAssertEqual(count, 1,
                       "writeMemoryChunk must fire when critic verdict is .pass")
    }

    func testMemoryWrittenWhenCriticSkipped() async throws {
        let spy = SpyXcalibreClient()
        let memSpy = SpyMemoryBackend()
        let engine = makeTestEngine(spy: spy, memoryBackend: memSpy, criticVerdict: .skipped)
        seedAssistantMessage(engine)

        try await runEngine(engine)

        let count = await memSpy.writeCallCount
        XCTAssertEqual(count, 1,
                       "writeMemoryChunk must fire when critic verdict is .skipped")
    }

    func testMemoryWrittenWhenCriticNotInvokedRoutineTask() async throws {
        let spy = SpyXcalibreClient()
        let memSpy = SpyMemoryBackend()
        // Routine task: critic branch not entered, lastCriticVerdict stays nil
        let engine = makeTestEngine(spy: spy,
                                    memoryBackend: memSpy,
                                    criticVerdict: .pass,      // irrelevant — not called
                                    classifierComplexity: .routine)
        seedAssistantMessage(engine)

        try await runEngine(engine)

        XCTAssertNil(engine.lastCriticVerdict,
                     "Routine task must not invoke critic; lastCriticVerdict stays nil")
        let count = await memSpy.writeCallCount
        XCTAssertEqual(count, 1,
                       "Memory write must still occur when critic is not invoked (routine task)")
    }
}
