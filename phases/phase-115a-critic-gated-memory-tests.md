# Phase 115a — CriticGatedMemoryTests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 114b complete: StagingBuffer accept/reject counters wired into OutcomeSignals.

Current state: AgenticEngine.runLoop evaluates the critic (CriticEngine) when complexity is
non-routine, but its verdict is a local `let verdict` scoped inside the while-loop guard block.
The memory write that follows the loop (xcalibreClient.writeMemoryChunk) runs unconditionally
whenever `memoriesEnabled = true` and the summary is non-empty. Low-quality sessions whose
critic verdict was `.fail` therefore enter the xcalibre memory store, polluting the RAG dataset
used by future sessions.

New surface introduced in phase 115b:
  - `AgenticEngine.lastCriticVerdict: CriticResult?` — stored on the instance; reset to nil at
    the start of each runLoop call; set inside the critic switch for pass / fail / skipped.
  - Memory write guard: if `case .fail = lastCriticVerdict { return }` — write skipped.
    nil (critic not invoked / routine task) and .pass / .skipped all allow the write.

TDD coverage:
  File 1 — CriticGatedMemoryTests: lastCriticVerdict nil at init; verdict stored after critic
            runs; memory not written on .fail; memory written on .pass; memory written on
            .skipped; memory written when critic not invoked (routine task).

---

## Write to: MerlinTests/Unit/CriticGatedMemoryTests.swift

```swift
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
    executeResponse: String = "The answer is 42.",
    criticVerdict: CriticResult = .pass,
    classifierComplexity: ComplexityTier = .standard
) -> AgenticEngine {
    let engine = makeEngine(
        provider: MockProvider(stubbedResponse: executeResponse),
        xcalibreClient: spy
    )
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
private func run(_ engine: AgenticEngine, message: String = "help me") async throws {
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
        let engine = makeTestEngine(spy: spy, criticVerdict: .fail("output was wrong"))
        seedAssistantMessage(engine)

        try await run(engine)

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

        try await run(engine)

        XCTAssertEqual(engine.lastCriticVerdict, .pass)
    }

    // MARK: - Memory write gating

    func testMemoryNotWrittenWhenCriticFails() async throws {
        let spy = SpyXcalibreClient()
        let engine = makeTestEngine(spy: spy, criticVerdict: .fail("wrong"))
        seedAssistantMessage(engine)

        try await run(engine)

        XCTAssertEqual(spy.writeCallCount, 0,
                       "writeMemoryChunk must be suppressed when critic verdict is .fail")
    }

    func testMemoryWrittenWhenCriticPasses() async throws {
        let spy = SpyXcalibreClient()
        let engine = makeTestEngine(spy: spy, criticVerdict: .pass)
        seedAssistantMessage(engine)

        try await run(engine)

        XCTAssertEqual(spy.writeCallCount, 1,
                       "writeMemoryChunk must fire when critic verdict is .pass")
    }

    func testMemoryWrittenWhenCriticSkipped() async throws {
        let spy = SpyXcalibreClient()
        let engine = makeTestEngine(spy: spy, criticVerdict: .skipped)
        seedAssistantMessage(engine)

        try await run(engine)

        XCTAssertEqual(spy.writeCallCount, 1,
                       "writeMemoryChunk must fire when critic verdict is .skipped")
    }

    func testMemoryWrittenWhenCriticNotInvokedRoutineTask() async throws {
        let spy = SpyXcalibreClient()
        // Routine task: critic branch not entered, lastCriticVerdict stays nil
        let engine = makeTestEngine(spy: spy,
                                    criticVerdict: .pass,      // irrelevant — not called
                                    classifierComplexity: .routine)
        seedAssistantMessage(engine)

        try await run(engine)

        XCTAssertNil(engine.lastCriticVerdict,
                     "Routine task must not invoke critic; lastCriticVerdict stays nil")
        XCTAssertEqual(spy.writeCallCount, 1,
                       "Memory write must still occur when critic is not invoked (routine task)")
    }
}
```

---

## Update: TestHelpers/EngineFactory.swift — add xcalibreClient parameter

```swift
// BEFORE:
@MainActor
func makeEngine(provider: MockProvider? = nil,
                proProvider: MockProvider? = nil,
                flashProvider: MockProvider? = nil) -> AgenticEngine {
    let memory = AuthMemory(storePath: "/dev/null")
    memory.addAllowPattern(tool: "*", pattern: "*")
    let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
    let router = ToolRouter(authGate: gate)
    let ctx = ContextManager()
    let pro = proProvider ?? provider ?? MockProvider(chunks: [])
    let flash = flashProvider ?? provider ?? MockProvider(chunks: [])
    return AgenticEngine(proProvider: pro, flashProvider: flash,
                         visionProvider: LMStudioProvider(),
                         toolRouter: router, contextManager: ctx)
}

// AFTER:
@MainActor
func makeEngine(provider: MockProvider? = nil,
                proProvider: MockProvider? = nil,
                flashProvider: MockProvider? = nil,
                xcalibreClient: (any XcalibreClientProtocol)? = nil) -> AgenticEngine {
    let memory = AuthMemory(storePath: "/dev/null")
    memory.addAllowPattern(tool: "*", pattern: "*")
    let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
    let router = ToolRouter(authGate: gate)
    let ctx = ContextManager()
    let pro = proProvider ?? provider ?? MockProvider(chunks: [])
    let flash = flashProvider ?? provider ?? MockProvider(chunks: [])
    return AgenticEngine(proProvider: pro, flashProvider: flash,
                         visionProvider: LMStudioProvider(),
                         toolRouter: router, contextManager: ctx,
                         xcalibreClient: xcalibreClient)
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
Expected: BUILD FAILED — `AgenticEngine.lastCriticVerdict` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/CriticGatedMemoryTests.swift \
        TestHelpers/EngineFactory.swift
git commit -m "Phase 115a — CriticGatedMemoryTests (failing)"
```
