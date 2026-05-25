# Task 151a — Context Pre-Run Compaction Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 150i complete: Copy Conversation (Cmd+Shift+A) in Edit menu.

New surface introduced in task 151b:
  - `ContextManager.preRunCompactionThreshold: Int` — token count above which `compactIfNeededBeforeRun` fires; default 10 000
  - `ContextManager.compactIfNeededBeforeRun(isContinuation: Bool)` — compacts when `estimatedTokens > preRunCompactionThreshold` and `isContinuation == false`
  - `AgenticEngine.runLoop(...)` — calls `context.compactIfNeededBeforeRun(isContinuation:)` before appending the user message
  - `MerlinCommands` Session menu — adds "Compact Context" button (Cmd+Shift+K) that calls `appState?.engine.contextManager.forceCompaction()`

TDD coverage:
  File 1 — ContextPreRunCompactionTests: unit tests for the new ContextManager methods
  File 2 — EnginePreRunCompactionIntegrationTests: engine-level integration test confirming compaction fires before the first LLM request

---

## Write to: MerlinTests/Unit/ContextPreRunCompactionTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class ContextPreRunCompactionTests: XCTestCase {

    // MARK: - preRunCompactionThreshold

    func testDefaultThresholdIs10000() {
        let cm = ContextManager()
        XCTAssertEqual(cm.preRunCompactionThreshold, 10_000)
    }

    // MARK: - compactIfNeededBeforeRun

    func testDoesNotCompactWhenUnderThreshold() {
        let cm = ContextManager()
        // Add a few small tool messages — well under 10 000 tokens
        for i in 0..<5 {
            cm.append(Message(
                role: .tool,
                content: .text("result \(i)"),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertLessThan(cm.estimatedTokens, cm.preRunCompactionThreshold)
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertEqual(cm.compactionCount, 0)
    }

    func testCompactsWhenOverThreshold() {
        let cm = ContextManager()
        // Each "x" * 3 500 is ~1 000 tokens; add 12 → ~12 000 tokens (> 10 000)
        for i in 0..<12 {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "x", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertGreaterThan(cm.estimatedTokens, cm.preRunCompactionThreshold)
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertEqual(cm.compactionCount, 1)
    }

    func testSkipsCompactionForContinuationTurns() {
        let cm = ContextManager()
        for i in 0..<12 {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "x", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertGreaterThan(cm.estimatedTokens, cm.preRunCompactionThreshold)
        cm.compactIfNeededBeforeRun(isContinuation: true)
        XCTAssertEqual(cm.compactionCount, 0)
    }

    func testTokensReducedAfterPreRunCompaction() {
        let cm = ContextManager()
        for i in 0..<12 {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "x", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        let tokensBefore = cm.estimatedTokens
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertLessThan(cm.estimatedTokens, tokensBefore)
    }

    func testUserAndAssistantMessagesPreservedAfterPreRunCompaction() {
        let cm = ContextManager()
        cm.append(Message(role: .user, content: .text("plan this"), timestamp: Date()))
        cm.append(Message(role: .assistant, content: .text("here is the plan"), timestamp: Date()))
        for i in 0..<12 {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "y", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertTrue(cm.messages.contains { $0.role == .user })
        XCTAssertTrue(cm.messages.contains { $0.role == .assistant })
    }
}
```

---

## Write to: MerlinTests/Unit/EnginePreRunCompactionIntegrationTests.swift

```swift
import XCTest
@testable import Merlin

/// Verifies that AgenticEngine calls compactIfNeededBeforeRun before the first
/// provider request when the context is over the threshold.
@MainActor
final class EnginePreRunCompactionIntegrationTests: XCTestCase {

    func testEngineCompactsBeforeRunWhenContextOverThreshold() async {
        let provider = MockProvider(chunks: [.assistant("done")])
        let engine = EngineFactory.make(provider: provider)

        // Pre-populate context above the pre-run compaction threshold.
        // Each message is ~1 000 tokens; 12 messages = ~12 000 tokens > 10 000 threshold.
        for i in 0..<12 {
            engine.contextManager.append(Message(
                role: .tool,
                content: .text(String(repeating: "z", count: 3_500)),
                toolCallId: "pre\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertGreaterThan(
            engine.contextManager.estimatedTokens,
            engine.contextManager.preRunCompactionThreshold
        )

        var events: [AgentEvent] = []
        for await event in engine.execute(userMessage: "summarise") {
            events.append(event)
        }

        // Compaction must have fired at least once before the provider was called.
        XCTAssertGreaterThanOrEqual(engine.contextManager.compactionCount, 1)
    }

    func testEngineDoesNotCompactWhenContextUnderThreshold() async {
        let provider = MockProvider(chunks: [.assistant("done")])
        let engine = EngineFactory.make(provider: provider)

        // Only a handful of small messages — under the threshold.
        for i in 0..<3 {
            engine.contextManager.append(Message(
                role: .tool,
                content: .text("small result \(i)"),
                toolCallId: "pre\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertLessThan(
            engine.contextManager.estimatedTokens,
            engine.contextManager.preRunCompactionThreshold
        )

        for await _ in engine.execute(userMessage: "hello") {}

        XCTAssertEqual(engine.contextManager.compactionCount, 0)
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
Expected: BUILD FAILED with errors naming `preRunCompactionThreshold` and `compactIfNeededBeforeRun` as missing symbols.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ContextPreRunCompactionTests.swift \
        MerlinTests/Unit/EnginePreRunCompactionIntegrationTests.swift
git commit -m "Task 151a — context pre-run compaction tests (failing)"
```
