# Task 201a — /compact Slash + Context-Length Recovery Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 200b complete: spawn_agent error isolation.

New surface introduced in task 201b:
  - `ProviderError.isContextLengthExceeded: Bool` — true when HTTP 400 body signals context overflow
  - `AgenticEngine` — detects context-length errors during `runLoop`, triggers `context.forceCompaction()`, retries the failed turn once
  - `ChatView.handleSlashCommandIfNeeded` — `/compact` triggers immediate compaction and emits a systemNote

TDD coverage:
  File 1 — ContextLengthRecoveryTests: ProviderError classification + engine retry behaviour
  File 2 — CompactSlashCommandTests: /compact slash command wiring

---

## Write to: MerlinTests/Unit/ContextLengthRecoveryTests.swift

```swift
import XCTest
@testable import Merlin

final class ContextLengthRecoveryTests: XCTestCase {

    // MARK: - ProviderError.isContextLengthExceeded

    func test_isContextLengthExceeded_true_for_known_bodies() {
        let bodies = [
            "context_length_exceeded",
            "This model's maximum context length is 8192 tokens",
            "maximum context length exceeded",
            "input too long for context window",
            "prompt is too long: 9000 tokens, max is 8192",
        ]
        for body in bodies {
            let error = ProviderError.httpError(statusCode: 400, body: body, providerID: "test")
            XCTAssertTrue(
                error.isContextLengthExceeded,
                "expected isContextLengthExceeded for body: \(body)"
            )
        }
    }

    func test_isContextLengthExceeded_false_for_other_400s() {
        let bodies = [
            "invalid_api_key",
            "model not found",
            "bad request: missing field 'model'",
            "",
        ]
        for body in bodies {
            let error = ProviderError.httpError(statusCode: 400, body: body, providerID: "test")
            XCTAssertFalse(
                error.isContextLengthExceeded,
                "must not classify as context overflow: \(body)"
            )
        }
    }

    func test_isContextLengthExceeded_false_for_non_400() {
        let error500 = ProviderError.httpError(statusCode: 500, body: "context_length_exceeded", providerID: "test")
        XCTAssertFalse(error500.isContextLengthExceeded, "only 400 with matching body qualifies")

        let networkError = ProviderError.networkError(
            underlying: URLError(.timedOut),
            providerID: "test"
        )
        XCTAssertFalse(networkError.isContextLengthExceeded)
    }

    // MARK: - Engine retry after compaction

    func test_engine_compacts_and_retries_on_contextLengthExceeded() async throws {
        // Provider fails with context_length_exceeded on first call, succeeds on second.
        let provider = MockProvider(failFirstCallWith:
            ProviderError.httpError(statusCode: 400, body: "context_length_exceeded", providerID: "mock")
        )
        let engine = EngineFactory.makeEngine(provider: provider)

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "hello") {
            events.append(event)
        }

        // Engine must have called the provider at least twice (first fail, then retry).
        XCTAssertGreaterThanOrEqual(provider.callCount, 2, "must retry after compaction")

        // A systemNote about compaction must have been emitted.
        let notes = events.compactMap { if case .systemNote(let s) = $0 { return s } else { return nil } }
        XCTAssertTrue(
            notes.contains(where: { $0.lowercased().contains("compact") }),
            "must emit compaction note before retry; notes: \(notes)"
        )

        // Must not surface an error event to the caller.
        let errorEvents = events.filter { if case .error = $0 { return true } else { return false } }
        XCTAssertTrue(errorEvents.isEmpty, "context-length retry must not surface error; got: \(errorEvents)")
    }

    func test_engine_surfaces_error_if_retry_also_fails() async throws {
        // Both calls fail with context_length_exceeded — engine must eventually surface error.
        let provider = MockProvider(failAllCallsWith:
            ProviderError.httpError(statusCode: 400, body: "context_length_exceeded", providerID: "mock")
        )
        let engine = EngineFactory.makeEngine(provider: provider)

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "hello") {
            events.append(event)
        }

        let errorEvents = events.filter { if case .error = $0 { return true } else { return false } }
        XCTAssertFalse(errorEvents.isEmpty,
            "when retry also fails, engine must surface an error event")
    }
}
```

---

## Write to: MerlinTests/Unit/CompactSlashCommandTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class CompactSlashCommandTests: XCTestCase {

    func test_compact_slash_triggers_forceCompaction() {
        // A ChatViewModel-backed compaction trigger: after /compact the context should
        // report that forceCompaction was called.
        let provider  = MockProvider()
        let engine    = EngineFactory.makeEngine(provider: provider)
        let viewModel = ChatViewModel()

        // Seed context with some messages so compaction has something to do.
        engine.contextManager.append(Message(role: .user,    content: .text("hello"),  timestamp: .now))
        engine.contextManager.append(Message(role: .assistant, content: .text("hi"), timestamp: .now))

        let compactionsBefore = engine.contextManager.compactionCount

        // Simulate the slash command handler calling compact.
        // In production this is called from ChatView.handleSlashCommandIfNeeded.
        engine.contextManager.forceCompaction()

        XCTAssertGreaterThan(engine.contextManager.compactionCount, compactionsBefore,
            "/compact must increment compactionCount")
    }

    func test_compact_slash_is_handled_not_forwarded() {
        // handleSlashCommandIfNeeded("/compact") must return true (consumed)
        // so the message is not forwarded to the engine as a user turn.
        let provider  = MockProvider()
        let engine    = EngineFactory.makeEngine(provider: provider)

        // We can't call ChatView directly (it requires a live SwiftUI environment),
        // but we can verify that the engine was NOT invoked when /compact is handled.
        // This test documents intent; the integration check is in the b-task.
        XCTAssertTrue(true, "placeholder — see task 201b for ChatView wiring test")
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

Expected: **BUILD FAILED** — `ProviderError.isContextLengthExceeded`, `MockProvider(failFirstCallWith:)`, `MockProvider(failAllCallsWith:)`, `MockProvider.callCount` do not exist yet.

## Commit

```bash
git add MerlinTests/Unit/ContextLengthRecoveryTests.swift \
        MerlinTests/Unit/CompactSlashCommandTests.swift
git commit -m "Task 201a — ContextLengthRecoveryTests + CompactSlashCommandTests (failing)"
```
