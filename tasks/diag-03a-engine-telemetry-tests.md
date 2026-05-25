# Phase diag-03a — Engine Telemetry Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-02b complete: provider telemetry instrumented.

New surface introduced in phase diag-03b:
  - `AgenticEngine.send()` emits:
      `engine.turn.start`    — turn, slot, provider_id, message_length
      `engine.turn.complete` — turn, slot, provider_id, total_duration_ms, tool_call_count, loop_count
      `engine.turn.error`    — turn, slot, provider_id, error_domain, error_code
  - `AgenticEngine` tool dispatch emits:
      `engine.tool.dispatched` — turn, tool_name, loop
      `engine.tool.complete`   — turn, tool_name, loop, duration_ms, result_bytes
      `engine.tool.error`      — turn, tool_name, loop, error_domain
  - `AgenticEngine.selectProvider(for:)` emits:
      `engine.provider.selected` — turn, slot, provider_id

TDD coverage:
  File 1 — EngineTelemetryTests: verify turn lifecycle events and tool dispatch events via mock provider + event capture

---

## Write to: MerlinTests/Unit/EngineTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class EngineTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-engine-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    // MARK: - Helpers

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

    private func events(named name: String, in events: [[String: Any]]) -> [[String: Any]] {
        events.filter { $0["event"] as? String == name }
    }

    private func makeEngine() async -> (AgenticEngine, MockTelemetryEngineProvider) {
        let provider = MockTelemetryEngineProvider()
        let engine = await AgenticEngine.makeForTesting(provider: provider)
        return (engine, provider)
    }

    // MARK: - Turn start / complete

    func testTurnStartEventEmitted() async throws {
        let (engine, provider) = await makeEngine()
        provider.streamResult = [CompletionChunk(delta: "hello", finishReason: "stop")]

        let stream = engine.send(userMessage: "hi there")
        for await _ in stream {}

        let captured = try await capturedEvents()
        let starts = events(named: "engine.turn.start", in: captured)
        XCTAssertFalse(starts.isEmpty, "engine.turn.start not emitted")
        let d = starts[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["turn"])
        XCTAssertNotNil(d?["slot"])
        XCTAssertNotNil(d?["message_length"])
    }

    func testTurnCompleteEventEmitted() async throws {
        let (engine, provider) = await makeEngine()
        provider.streamResult = [CompletionChunk(delta: "done", finishReason: "stop")]

        let stream = engine.send(userMessage: "finish this")
        for await _ in stream {}

        let captured = try await capturedEvents()
        let completes = events(named: "engine.turn.complete", in: captured)
        XCTAssertFalse(completes.isEmpty, "engine.turn.complete not emitted")
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["turn"])
        XCTAssertNotNil(d?["total_duration_ms"])
        let ms = d?["total_duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }

    func testTurnCompleteIncludesLoopCount() async throws {
        let (engine, provider) = await makeEngine()
        provider.streamResult = [CompletionChunk(delta: "result", finishReason: "stop")]

        let stream = engine.send(userMessage: "test loop count")
        for await _ in stream {}

        let captured = try await capturedEvents()
        let completes = events(named: "engine.turn.complete", in: captured)
        XCTAssertFalse(completes.isEmpty)
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["loop_count"])
    }

    func testTurnErrorEventEmittedOnProviderFailure() async throws {
        let (engine, provider) = await makeEngine()
        provider.shouldThrow = true

        let stream = engine.send(userMessage: "fail me")
        for await _ in stream {}

        let captured = try await capturedEvents()
        let errors = events(named: "engine.turn.error", in: captured)
        XCTAssertFalse(errors.isEmpty, "engine.turn.error not emitted on failure")
        let d = errors[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["turn"])
    }

    // MARK: - Provider selected

    func testProviderSelectedEventEmitted() async throws {
        let (engine, provider) = await makeEngine()
        provider.streamResult = [CompletionChunk(delta: "hi", finishReason: "stop")]

        let stream = engine.send(userMessage: "select provider")
        for await _ in stream {}

        let captured = try await capturedEvents()
        let selected = events(named: "engine.provider.selected", in: captured)
        XCTAssertFalse(selected.isEmpty, "engine.provider.selected not emitted")
        let d = selected[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["provider_id"])
        XCTAssertNotNil(d?["slot"])
    }

    // MARK: - Tool dispatch

    func testToolDispatchedEventEmitted() async throws {
        let (engine, provider) = await makeEngine()
        // First stream: model requests a tool call
        provider.streamResult = [
            CompletionChunk(
                delta: "",
                toolCallChunks: [ToolCallChunk(index: 0, id: "call-1", name: "read_file",
                                               arguments: "{\"path\":\"/tmp/test.txt\"}")],
                finishReason: "tool_calls"
            )
        ]
        // Second stream: model finishes after tool result
        provider.secondStreamResult = [CompletionChunk(delta: "done", finishReason: "stop")]

        engine.registerTool("read_file") { _ in "file contents" }

        let stream = engine.send(userMessage: "read a file")
        for await _ in stream {}

        let captured = try await capturedEvents()
        let dispatched = events(named: "engine.tool.dispatched", in: captured)
        XCTAssertFalse(dispatched.isEmpty, "engine.tool.dispatched not emitted")
        let d = dispatched[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["tool_name"] as? String, "read_file")
        XCTAssertNotNil(d?["loop"])
    }

    func testToolCompleteEventEmitted() async throws {
        let (engine, provider) = await makeEngine()
        provider.streamResult = [
            CompletionChunk(
                delta: "",
                toolCallChunks: [ToolCallChunk(index: 0, id: "call-2", name: "read_file",
                                               arguments: "{\"path\":\"/tmp/test.txt\"}")],
                finishReason: "tool_calls"
            )
        ]
        provider.secondStreamResult = [CompletionChunk(delta: "done", finishReason: "stop")]

        engine.registerTool("read_file") { _ in "file contents" }

        let stream = engine.send(userMessage: "complete tool")
        for await _ in stream {}

        let captured = try await capturedEvents()
        let complete = events(named: "engine.tool.complete", in: captured)
        XCTAssertFalse(complete.isEmpty, "engine.tool.complete not emitted")
        let d = complete[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["tool_name"] as? String, "read_file")
        XCTAssertNotNil(d?["duration_ms"])
        XCTAssertNotNil(d?["result_bytes"])
    }

    func testToolErrorEventEmittedWhenToolThrows() async throws {
        let (engine, provider) = await makeEngine()
        provider.streamResult = [
            CompletionChunk(
                delta: "",
                toolCallChunks: [ToolCallChunk(index: 0, id: "call-3", name: "broken_tool",
                                               arguments: "{}")],
                finishReason: "tool_calls"
            )
        ]
        provider.secondStreamResult = [CompletionChunk(delta: "recovered", finishReason: "stop")]

        engine.registerTool("broken_tool") { _ in throw URLError(.badURL) }

        let stream = engine.send(userMessage: "trigger error")
        for await _ in stream {}

        let captured = try await capturedEvents()
        let errors = events(named: "engine.tool.error", in: captured)
        XCTAssertFalse(errors.isEmpty, "engine.tool.error not emitted when tool throws")
        let d = errors[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["tool_name"] as? String, "broken_tool")
    }
}

// MARK: - Test helpers

/// Minimal mock provider for engine telemetry tests.
final class MockTelemetryEngineProvider: LLMProvider, @unchecked Sendable {
    var id: String = "mock-engine-provider"
    var baseURL: URL = URL(string: "http://localhost")!
    var streamResult: [CompletionChunk] = []
    var secondStreamResult: [CompletionChunk] = []
    var shouldThrow: Bool = false
    private var callCount = 0

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        if shouldThrow { throw URLError(.badServerResponse) }
        callCount += 1
        let chunks = callCount == 1 ? streamResult : secondStreamResult
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

extension AgenticEngine {
    /// Creates a minimal engine wired to a single provider, suitable for unit tests.
    @MainActor
    static func makeForTesting(provider: any LLMProvider) async -> AgenticEngine {
        let engine = AgenticEngine()
        await engine.setRegistryForTesting(provider: provider)
        return engine
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
Expected: BUILD FAILED — `engine.turn.start`, `engine.tool.dispatched` events not yet emitted; `setRegistryForTesting` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/EngineTelemetryTests.swift
git commit -m "Phase diag-03a — Engine telemetry tests (failing)"
```
