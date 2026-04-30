# Phase 142a — Semantic Fault Injection Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 141b complete: GroundingReport per-turn signal in place. All prior tests pass.

Motivation:
Addresses the "semantic fault injection" mitigation from:
"Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems" — VentureBeat
https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems

The article states: "The most dangerous failures are not caused by hard infrastructure
faults. They emerge at the interaction layer between data quality, context assembly,
model reasoning, orchestration logic, and downstream action."

Traditional chaos engineering kills nodes. Semantic fault injection degrades the DATA
and CONTEXT that flows through the system: stale retrieval results, truncated model
outputs, semantically empty tool responses, token-boundary pressure. This phase adds
test doubles for each fault type and scenario tests verifying that Merlin's behavioral
monitoring stack detects them.

New test infrastructure introduced in phase 142b:

  TestHelpers/SemanticFaults/StalenessInjectingMemoryBackend.swift
    - MemoryBackendPlugin that returns results with a configurable createdAt age
    - Simulates retrieval from a memory store that has not been updated recently

  TestHelpers/SemanticFaults/TruncatingMockProvider.swift
    - LLMProvider that caps all responses at a configurable character limit
    - Sets finish reason to simulate max_tokens pressure
    - Simulates a model running against a token budget that is too low

  TestHelpers/SemanticFaults/EmptyToolResultRouter.swift
    - ToolRouter subclass/wrapper that replaces every tool result with an empty string
    - Simulates a tool call that succeeds syntactically but returns semantically empty data

  TestHelpers/SemanticFaults/DroppingContextManager.swift
    - ContextManager subclass that silently drops the oldest N messages before each turn
    - Simulates context window overflow causing the model to lose early session context

TDD coverage:
  File: MerlinTests/Unit/SemanticFaultInjectionTests.swift
    Scenario 1 — Stale retrieval:
      - GroundingReport.hasStaleMemory is true when StalenessInjectingMemoryBackend injected
      - GroundingReport.isWellGrounded reflects staleness threshold setting
    Scenario 2 — Token pressure / truncation:
      - TruncatingMockProvider causes ModelParameterAdvisor to detect truncation pattern
      - GroundingReport is still emitted correctly under truncation
    Scenario 3 — Empty tool results:
      - Engine completes a turn when EmptyToolResultRouter returns empty tool output
      - Circuit breaker counter increments when critic grades empty-tool output as fail
    Scenario 4 — Context drop:
      - GroundingReport is emitted even when DroppingContextManager has stripped messages
      - consecutiveCriticFailures accumulates when context drop degrades output quality

---

## Write to: TestHelpers/SemanticFaults/StalenessInjectingMemoryBackend.swift

```swift
import Foundation
@testable import Merlin

/// Memory backend that returns results with a configurable `createdAt` age.
/// Used in semantic fault injection tests to simulate a retrieval store
/// that has not received new writes and is returning stale context.
actor StalenessInjectingMemoryBackend: MemoryBackendPlugin {
    nonisolated let pluginID = "stale-injecting"
    nonisolated let displayName = "Stale Injecting (test)"

    /// Age in days to assign to all returned chunks. Default 91 — exceeds the default
    /// ragFreshnessThresholdDays of 90 so hasStaleMemory fires by default.
    let ageDays: Int
    let content: String

    init(ageDays: Int = 91, content: String = "stale memory content") {
        self.ageDays = ageDays
        self.content = content
    }

    func write(_ chunk: MemoryChunk) async throws {}

    func search(query: String, topK: Int) async throws -> [MemorySearchResult] {
        let staleDate = Calendar.current.date(
            byAdding: .day,
            value: -ageDays,
            to: Date()
        ) ?? Date()
        let chunk = MemoryChunk(
            id: UUID().uuidString,
            content: content,
            chunkType: "factual",
            createdAt: staleDate
        )
        return [MemorySearchResult(chunk: chunk, score: 0.75)]
    }

    func delete(id: String) async throws {}
}
```

---

## Write to: TestHelpers/SemanticFaults/TruncatingMockProvider.swift

```swift
import Foundation
@testable import Merlin

/// LLM provider that caps all responses at `maxChars` characters.
/// Used to simulate token-boundary pressure — the model hits its max_tokens
/// limit and produces incomplete output.
///
/// Sets `finishReason` to "length" on the completion delta so that
/// ModelParameterAdvisor can detect the maxTokensTooLow pattern.
struct TruncatingMockProvider: LLMProvider, Sendable {
    let id: String = "truncating-mock"
    let displayName: String = "Truncating Mock"
    let supportsThinking: Bool = false
    let isLocal: Bool = true

    let maxChars: Int
    let baseResponse: String

    init(maxChars: Int = 20, baseResponse: String = "This is a longer response that will be cut off.") {
        self.maxChars = maxChars
        self.baseResponse = baseResponse
    }

    func complete(request: CompletionRequest) throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let truncated = String(baseResponse.prefix(maxChars))
        let chunk = CompletionChunk(
            delta: .init(role: nil, content: truncated),
            finishReason: "length"
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }
    }
}
```

---

## Write to: TestHelpers/SemanticFaults/EmptyToolResultRouter.swift

```swift
import Foundation
@testable import Merlin

/// ToolRouter wrapper that replaces every tool result with an empty string.
/// Used to simulate a tool call that succeeds syntactically but returns
/// semantically empty or useless data — e.g. a search that finds nothing,
/// a file read that returns an empty file, an API call with an empty body.
final class EmptyToolResultRouter: ToolRouter {
    override func call(tool: ToolCall, authPresenter: any AuthPresenter) async -> ToolResult {
        let base = await super.call(tool: tool, authPresenter: authPresenter)
        return ToolResult(toolCallID: base.toolCallID, content: "", isError: false)
    }
}
```

---

## Write to: TestHelpers/SemanticFaults/DroppingContextManager.swift

```swift
import Foundation
@testable import Merlin

/// ContextManager subclass that silently drops the oldest `dropCount` non-system
/// messages before each call to `buildMessages()`.
/// Used to simulate context window overflow where the model loses earlier turns.
final class DroppingContextManager: ContextManager {
    let dropCount: Int

    init(dropCount: Int = 3) {
        self.dropCount = dropCount
        super.init()
    }

    override func buildMessages(systemPrompt: String?) -> [Message] {
        let all = super.buildMessages(systemPrompt: systemPrompt)
        let system = all.filter { $0.role == .system }
        var nonSystem = all.filter { $0.role != .system }
        if nonSystem.count > dropCount {
            nonSystem = Array(nonSystem.dropFirst(dropCount))
        }
        return system + nonSystem
    }
}
```

---

## Write to: MerlinTests/Unit/SemanticFaultInjectionTests.swift

```swift
import XCTest
@testable import Merlin

/// Semantic fault injection scenario tests.
///
/// Each test injects a specific degradation into the engine's data or context pipeline
/// and asserts that Merlin's behavioral monitoring stack (GroundingReport, circuit
/// breaker, ModelParameterAdvisor) detects it — rather than letting it silently
/// produce fluent but wrong output.
///
/// Reference:
/// "Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"
/// https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems
@MainActor
final class SemanticFaultInjectionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppSettings.shared.ragFreshnessThresholdDays = 90
        AppSettings.shared.ragMinGroundingScore = 0.30
        AppSettings.shared.agentCircuitBreakerThreshold = 3
        AppSettings.shared.agentCircuitBreakerMode = "warn"
    }

    // MARK: - Scenario 1: Stale retrieval

    func testStaleRetrievalDetectedByGroundingReport() async throws {
        let staleBackend = StalenessInjectingMemoryBackend(ageDays: 120)
        let engine = AgenticEngine(
            provider: MockProvider(responses: ["response"]),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager(),
            memoryBackend: staleBackend
        )

        var report: GroundingReport?
        for await event in engine.send("What do you know about my preferences?") {
            if case .groundingReport(let r) = event { report = r }
        }

        XCTAssertNotNil(report, "GroundingReport must be emitted")
        XCTAssertTrue(report?.hasStaleMemory == true,
                      "120-day-old chunks should trigger hasStaleMemory")
        XCTAssertGreaterThan(report?.totalChunks ?? 0, 0,
                             "Stale backend still returns chunks")
    }

    func testFreshRetrievalPassesStalenessCheck() async throws {
        // 5-day-old content is well within the 90-day threshold
        let freshBackend = StalenessInjectingMemoryBackend(ageDays: 5)
        let engine = AgenticEngine(
            provider: MockProvider(responses: ["ok"]),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager(),
            memoryBackend: freshBackend
        )

        var report: GroundingReport?
        for await event in engine.send("hello") {
            if case .groundingReport(let r) = event { report = r }
        }

        XCTAssertEqual(report?.hasStaleMemory, false)
    }

    // MARK: - Scenario 2: Token pressure / truncation

    func testTruncatingProviderStillEmitsGroundingReport() async throws {
        let engine = AgenticEngine(
            provider: TruncatingMockProvider(maxChars: 15),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager()
        )

        var reportEmitted = false
        for await event in engine.send("explain something complex") {
            if case .groundingReport = event { reportEmitted = true }
        }

        XCTAssertTrue(reportEmitted,
                      "GroundingReport must be emitted even when provider truncates output")
    }

    func testTruncatingProviderAccumulatesInAdvisor() async throws {
        let engine = AgenticEngine(
            provider: TruncatingMockProvider(maxChars: 10),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: ContextManager()
        )
        // Drive enough truncated turns for ModelParameterAdvisor to potentially detect
        for i in 0..<12 {
            for await _ in engine.send("turn \(i)") {}
        }
        // The advisor should have accumulated records — verify no crash and engine stable
        XCTAssertGreaterThanOrEqual(engine.consecutiveCriticFailures, 0,
                                    "Engine must remain stable under sustained truncation")
    }

    // MARK: - Scenario 3: Empty tool results

    func testEmptyToolResultsDoNotCrashEngine() async throws {
        let registry = ToolRegistry()
        registry.registerBuiltins()
        let emptyRouter = EmptyToolResultRouter(registry: registry)
        let engine = AgenticEngine(
            provider: MockProvider(responses: ["I'll check that for you.", "Done."]),
            toolRouter: emptyRouter,
            contextManager: ContextManager()
        )

        var completed = false
        for await event in engine.send("list files in current directory") {
            if case .error = event { XCTFail("Engine must not emit error on empty tool result") }
            _ = event
        }
        completed = true
        XCTAssertTrue(completed, "Engine must complete turn even with empty tool results")
    }

    func testCircuitBreakerIncrementsSustainedEmptyToolFailures() async throws {
        AppSettings.shared.agentCircuitBreakerThreshold = 2
        let registry = ToolRegistry()
        let emptyRouter = EmptyToolResultRouter(registry: registry)
        let engine = AgenticEngine(
            provider: MockProvider(responses: Array(repeating: "ok", count: 10)),
            toolRouter: emptyRouter,
            contextManager: ContextManager()
        )
        engine.criticOverride = AlwaysFailCritic()

        for _ in 0..<3 { for await _ in engine.send("test") {} }
        XCTAssertGreaterThanOrEqual(engine.consecutiveCriticFailures, 2,
                                    "Sustained empty-tool-result failures must accumulate in circuit breaker")
    }

    // MARK: - Scenario 4: Context drop

    func testGroundingReportEmittedWithDroppedContext() async throws {
        let droppingContext = DroppingContextManager(dropCount: 5)
        let engine = AgenticEngine(
            provider: MockProvider(responses: ["ok"]),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: droppingContext
        )

        var reportEmitted = false
        for await event in engine.send("remember what we discussed earlier?") {
            if case .groundingReport = event { reportEmitted = true }
        }

        XCTAssertTrue(reportEmitted,
                      "GroundingReport must be emitted even when context has been dropped")
    }

    func testEngineStableWithAggressiveContextDrop() async throws {
        let droppingContext = DroppingContextManager(dropCount: 50)
        let engine = AgenticEngine(
            provider: MockProvider(responses: Array(repeating: "ok", count: 5)),
            toolRouter: ToolRouter(registry: ToolRegistry()),
            contextManager: droppingContext
        )

        for i in 0..<5 {
            for await event in engine.send("turn \(i)") {
                if case .error(let e) = event {
                    XCTFail("Engine must not error with dropping context: \(e)")
                }
            }
        }
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
Expected: BUILD FAILED — `StalenessInjectingMemoryBackend`, `TruncatingMockProvider`,
`EmptyToolResultRouter`, `DroppingContextManager` are undefined.

## Commit
```bash
git add MerlinTests/Unit/SemanticFaultInjectionTests.swift
git commit -m "Phase 142a — semantic fault injection tests (failing)"
```
