# Phase diag-05a — Context, Planner & Critic Telemetry Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-04b complete: memory & RAG telemetry instrumented.

New surface introduced in phase diag-05b:
  - `ContextManager.compact(force:)` emits:
      `context.compaction`      — message_count_before, message_count_after, tokens_before, tokens_after, forced
  - `PlannerEngine.classify(message:domain:)` emits:
      `planner.classify`        — complexity, reason, duration_ms, used_llm
  - `PlannerEngine.decompose(task:context:)` emits:
      `planner.decompose.start` — task_length
      `planner.decompose.complete` — duration_ms, step_count
      `planner.decompose.error`    — error_domain
  - `CriticEngine.evaluate(...)` emits:
      `critic.evaluate.start`   — task_type
      `critic.evaluate.complete` — duration_ms, result (pass/fail/skipped), stage
      `critic.evaluate.fail`    — reason, stage

TDD coverage:
  File 1 — ContextCompactionTelemetryTests: verify compaction event fires with correct before/after counts
  File 2 — PlannerTelemetryTests: verify classify and decompose events
  File 3 — CriticTelemetryTests: verify evaluate events on pass and fail

---

## Write to: MerlinTests/Unit/ContextCompactionTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class ContextCompactionTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-ctx-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    func testCompactionEventEmittedOnForceCompact() async throws {
        let ctx = ContextManager()
        // Add enough messages to have something to compact
        for i in 0..<20 {
            ctx.append(Message(role: .user, content: .text("Message \(i) with some content"),
                               timestamp: Date()))
            ctx.append(Message(role: .assistant, content: .text("Reply \(i) with response content"),
                               timestamp: Date()))
        }

        ctx.forceCompaction()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "context.compaction" }
        XCTAssertFalse(events.isEmpty, "context.compaction not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["message_count_before"])
        XCTAssertNotNil(d?["message_count_after"])
        XCTAssertNotNil(d?["tokens_before"])
        let forced = d?["forced"] as? Bool
        XCTAssertEqual(forced, true)
    }

    func testCompactionCountsArePlausible() async throws {
        let ctx = ContextManager()
        for i in 0..<30 {
            ctx.append(Message(role: .user,
                               content: .text("Long user message number \(i) — adding plenty of tokens"),
                               timestamp: Date()))
            ctx.append(Message(role: .assistant,
                               content: .text("Lengthy assistant reply \(i) with substantial content here"),
                               timestamp: Date()))
        }

        let countBefore = ctx.messages.count
        ctx.forceCompaction()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "context.compaction" }
        XCTAssertFalse(events.isEmpty)
        let d = events[0]["data"] as? [String: Any]
        let before = d?["message_count_before"] as? Int ?? 0
        let after  = d?["message_count_after"]  as? Int ?? before
        XCTAssertEqual(before, countBefore)
        XCTAssertLessThanOrEqual(after, before)
    }
}
```

---

## Write to: MerlinTests/Unit/PlannerTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class PlannerTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-planner-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    private func makePlanner(response: String = "") -> PlannerEngine {
        let provider = MockPlannerProvider(response: response)
        return PlannerEngine(orchestrateProvider: provider)
    }

    func testClassifyEmitsTelemetry() async throws {
        let planner = makePlanner()
        let domain = SoftwareDomain()

        _ = await planner.classify(message: "write a quick hello world", domain: domain)

        let captured = try await capturedEvents()
        let classifyEvents = captured.filter { $0["event"] as? String == "planner.classify" }
        XCTAssertFalse(classifyEvents.isEmpty, "planner.classify not emitted")
        let d = classifyEvents[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["complexity"])
        XCTAssertNotNil(d?["reason"])
    }

    func testClassifyEventIncludesDuration() async throws {
        let planner = makePlanner()
        let domain = SoftwareDomain()

        _ = await planner.classify(message: "refactor entire auth system", domain: domain)

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "planner.classify" }
        XCTAssertFalse(events.isEmpty)
        let ms = events[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }

    func testDecomposeStartEmitted() async throws {
        let planner = makePlanner(response: "{\"steps\":[{\"description\":\"step1\",\"successCriteria\":\"ok\",\"complexity\":\"routine\"}]}")

        _ = await planner.decompose(task: "build feature X", context: [])

        let captured = try await capturedEvents()
        let starts = captured.filter { $0["event"] as? String == "planner.decompose.start" }
        XCTAssertFalse(starts.isEmpty, "planner.decompose.start not emitted")
        let d = starts[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["task_length"])
    }

    func testDecomposeCompleteEmitted() async throws {
        let planner = makePlanner(response: "{\"steps\":[{\"description\":\"s1\",\"successCriteria\":\"c1\",\"complexity\":\"routine\"},{\"description\":\"s2\",\"successCriteria\":\"c2\",\"complexity\":\"standard\"}]}")

        let steps = await planner.decompose(task: "build feature X", context: [])

        let captured = try await capturedEvents()
        let completes = captured.filter { $0["event"] as? String == "planner.decompose.complete" }
        XCTAssertFalse(completes.isEmpty, "planner.decompose.complete not emitted")
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["step_count"] as? Int, steps.count)
        let ms = completes[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }
}

// MARK: - Helpers

final class MockPlannerProvider: LLMProvider, @unchecked Sendable {
    var id: String = "mock-planner"
    var baseURL: URL = URL(string: "http://localhost")!
    var response: String

    init(response: String) { self.response = response }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(delta: text, finishReason: "stop"))
            continuation.finish()
        }
    }
}

extension PlannerEngine {
    convenience init(orchestrateProvider: any LLMProvider) {
        self.init()
        self.orchestrateProvider = orchestrateProvider
    }
}
```

---

## Write to: MerlinTests/Unit/CriticTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class CriticTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-critic-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    private func makeCritic(
        stage1Shell: MockShellRunner = MockShellRunner(exitCode: 0, output: "ok"),
        stage2Response: String = "{\"passed\":true,\"reason\":\"looks good\"}"
    ) -> CriticEngine {
        let provider = MockCriticProvider(response: stage2Response)
        return CriticEngine(
            verificationBackend: MockCriticVerificationBackend(),
            shellRunner: stage1Shell,
            orchestrateProvider: provider
        )
    }

    func testCriticEvaluateStartEmitted() async throws {
        let critic = makeCritic()
        let taskType = DomainTaskType(domainID: "software", name: "general", displayName: "General")

        _ = await critic.evaluate(taskType: taskType, output: "output", context: [])

        let captured = try await capturedEvents()
        let starts = captured.filter { $0["event"] as? String == "critic.evaluate.start" }
        XCTAssertFalse(starts.isEmpty, "critic.evaluate.start not emitted")
        let d = starts[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["task_type"])
    }

    func testCriticEvaluateCompleteOnPass() async throws {
        let critic = makeCritic()
        let taskType = DomainTaskType(domainID: "software", name: "general", displayName: "General")

        let result = await critic.evaluate(taskType: taskType, output: "output", context: [])

        let captured = try await capturedEvents()
        let completes = captured.filter { $0["event"] as? String == "critic.evaluate.complete" }
        XCTAssertFalse(completes.isEmpty, "critic.evaluate.complete not emitted")
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["result"])
        let ms = completes[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
        _ = result // suppress warning
    }

    func testCriticEvaluateFailEmitted() async throws {
        let shell = MockShellRunner(exitCode: 1, output: "test failed")
        let critic = makeCritic(stage1Shell: shell)
        let taskType = DomainTaskType(domainID: "software", name: "general", displayName: "General")

        let result = await critic.evaluate(taskType: taskType, output: "output", context: [])

        let captured = try await capturedEvents()
        let fails = captured.filter { $0["event"] as? String == "critic.evaluate.fail" }
        if case .fail = result {
            XCTAssertFalse(fails.isEmpty, "critic.evaluate.fail not emitted on failure")
            let d = fails[0]["data"] as? [String: Any]
            XCTAssertNotNil(d?["reason"])
        }
    }
}

// MARK: - Helpers

final class MockCriticProvider: LLMProvider, @unchecked Sendable {
    var id: String = "mock-critic"
    var baseURL: URL = URL(string: "http://localhost")!
    var response: String

    init(response: String) { self.response = response }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(delta: text, finishReason: "stop"))
            continuation.finish()
        }
    }
}

final class MockShellRunner: ShellRunning, @unchecked Sendable {
    let exitCode: Int
    let output: String
    init(exitCode: Int, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
    func run(_ command: String) async -> (exitCode: Int, output: String) {
        (exitCode, output)
    }
}

final class MockCriticVerificationBackend: VerificationBackend, @unchecked Sendable {
    func verificationCommands(for taskType: DomainTaskType) async -> [VerificationCommand]? {
        // Return a single command so stage1 runs
        [VerificationCommand(command: "exit 0", description: "mock check")]
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
Expected: BUILD FAILED — `context.compaction`, `planner.classify`, `critic.evaluate.start` events not yet emitted; `PlannerEngine.init(orchestrateProvider:)` convenience init not yet defined.

## Commit
```bash
git add MerlinTests/Unit/ContextCompactionTelemetryTests.swift \
        MerlinTests/Unit/PlannerTelemetryTests.swift \
        MerlinTests/Unit/CriticTelemetryTests.swift
git commit -m "Phase diag-05a — Context, planner & critic telemetry tests (failing)"
```
