# Task 198a — Async Tool Dispatch Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 197b complete: stable prefix cache for system prompt.

## Problem
`AgenticEngine` calls `toolRouter.dispatch([singleCall])` inside a sequential `for` loop —
one call at a time. `ToolRouter.dispatch()` already parallelises an array of calls via
`TaskGroup`, but that parallelism is never used because only single-element arrays are
passed. When the model emits N tool calls in one streaming response (e.g. reading 4 files),
execution is fully sequential even though the calls are independent.

## Fix (implemented in 198b)
Replace the per-call dispatch loop with a two-task approach:

**Task 1 — sequential pre-hooks** (preserves hook ordering guarantees):
Iterate `regularCalls`, run `hookEngine.runPreToolUse` for each. Collect allowed calls;
produce denied `ToolResult` inline for blocked ones.

**Task 2 — batch dispatch**:
Pass ALL allowed calls to `toolRouter.dispatch(allowedCalls)` in a single call. The
existing `TaskGroup` inside `ToolRouter.dispatch` runs them in parallel.

**Task 3 — sequential context updates**:
Walk the results in original call order. Emit telemetry, append tool messages to context,
run `hookEngine.runPostToolUse` — preserving message ordering for the OpenAI wire format.

## New surface in task 198b
- `AgenticEngine` pre-hook + batch dispatch pattern (no new public API — internal refactor)
- `ToolRouter` unchanged — its existing `dispatch(_ calls: [ToolCall])` signature is correct

TDD coverage:
  File — AsyncToolDispatchTests.swift: 4 tests (via MockToolRouter that records call batches)

Note: `MockToolRouter` must be added to `TestHelpers/` so it is available to all test targets.

---

## Write to: TestHelpers/MockToolRouter.swift

```swift
// MockToolRouter.swift
// Task 198a — records how dispatch() is called for inspection in tests.
import Foundation
@testable import Merlin

/// A ToolRouter subclass that records every dispatch() invocation.
/// Returned results are configurable per call-batch; defaults to empty success.
@MainActor
final class MockToolRouter: ToolRouter {

    struct DispatchRecord {
        let calls: [ToolCall]
        let timestamp: Date
    }

    private(set) var dispatchRecords: [DispatchRecord] = []
    var resultFactory: ([ToolCall]) -> [ToolResult] = { calls in
        calls.map { ToolResult(toolCallId: $0.id, content: "ok", isError: false) }
    }

    override func dispatch(_ calls: [ToolCall]) async -> [ToolResult] {
        dispatchRecords.append(DispatchRecord(calls: calls, timestamp: Date()))
        return resultFactory(calls)
    }
}
```

## Write to: MerlinTests/Unit/AsyncToolDispatchTests.swift

```swift
// AsyncToolDispatchTests.swift
// Task 198a — failing tests for batch tool dispatch.
import XCTest
@testable import Merlin

@MainActor
final class AsyncToolDispatchTests: XCTestCase {

    // MARK: - Batch dispatch

    /// When a single streaming response contains N regular tool calls, dispatch() must be
    /// called exactly ONCE with all N calls — not N times with one call each.
    /// FAILS before 198b — the current loop calls dispatch([call]) N times.
    func test_multipleToolCalls_areDispatchedInOneBatch() async throws {
        let router = MockToolRouter(authGate: NullAuthGate())
        let engine = EngineFactory.make(toolRouter: router)

        // Simulate 3 independent tool calls arriving in one streaming response
        let calls = (1...3).map { i in
            ToolCall(id: "id-\(i)", type: "function",
                     function: FunctionCall(name: "read_file", arguments: #"{"path":"/tmp/f\#(i)"}"#))
        }

        await engine.dispatchRegularCalls(calls, turn: 1, loopCount: 0,
                                          writtenFilePaths: &[], continuation: .dummy)

        XCTAssertEqual(router.dispatchRecords.count, 1,
                       "dispatch() must be called once with all calls, not per-call")
        XCTAssertEqual(router.dispatchRecords.first?.calls.count, 3)
    }

    /// A call denied by a pre-tool hook must NOT appear in the dispatch batch.
    /// FAILS before 198b — dispatchRegularCalls() does not exist.
    func test_hookedDenialIsExcludedFromBatch() async throws {
        let router = MockToolRouter(authGate: NullAuthGate())
        let hooks = [Hook(event: .preToolUse, matcher: .toolName("write_file"),
                          command: "echo denied", action: .deny)]
        let engine = EngineFactory.make(toolRouter: router, hooks: hooks)

        let calls = [
            ToolCall(id: "a", type: "function",
                     function: FunctionCall(name: "write_file", arguments: #"{"path":"/tmp/x"}"#)),
            ToolCall(id: "b", type: "function",
                     function: FunctionCall(name: "read_file", arguments: #"{"path":"/tmp/y"}"#))
        ]

        var written: [String] = []
        await engine.dispatchRegularCalls(calls, turn: 1, loopCount: 0,
                                          writtenFilePaths: &written, continuation: .dummy)

        XCTAssertEqual(router.dispatchRecords.count, 1)
        XCTAssertEqual(router.dispatchRecords.first?.calls.count, 1,
                       "only the allowed read_file call should reach the router")
        XCTAssertEqual(router.dispatchRecords.first?.calls.first?.id, "b")
    }

    /// Results must be appended to context in original call order, regardless of
    /// parallel execution order inside the router.
    /// FAILS before 198b — dispatchRegularCalls() does not exist.
    func test_resultsAreAppliedInOriginalCallOrder() async throws {
        let router = MockToolRouter(authGate: NullAuthGate())
        // Return results in reverse order to test ordering
        router.resultFactory = { calls in
            calls.reversed().map { ToolResult(toolCallId: $0.id, content: "result-\($0.id)", isError: false) }
        }
        let engine = EngineFactory.make(toolRouter: router)

        let calls = ["x", "y", "z"].map { id in
            ToolCall(id: id, type: "function",
                     function: FunctionCall(name: "read_file", arguments: #"{"path":"/tmp/\#(id)"}"#))
        }

        var written: [String] = []
        await engine.dispatchRegularCalls(calls, turn: 1, loopCount: 0,
                                          writtenFilePaths: &written, continuation: .dummy)

        // Tool result messages appended to context must be x, y, z in that order
        let toolMessages = engine.contextManager.messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.map { $0.toolCallId }, ["x", "y", "z"])
    }

    /// write_file paths must still be tracked even when dispatched in a batch.
    /// FAILS before 198b — dispatchRegularCalls() does not exist.
    func test_writeFilePaths_trackedAcrossBatch() async throws {
        let router = MockToolRouter(authGate: NullAuthGate())
        let engine = EngineFactory.make(toolRouter: router)

        let calls = [
            ToolCall(id: "w1", type: "function",
                     function: FunctionCall(name: "write_file", arguments: #"{"path":"/out/a.txt","content":"x"}"#)),
            ToolCall(id: "w2", type: "function",
                     function: FunctionCall(name: "write_file", arguments: #"{"path":"/out/b.txt","content":"y"}"#))
        ]

        var written: [String] = []
        await engine.dispatchRegularCalls(calls, turn: 1, loopCount: 0,
                                          writtenFilePaths: &written, continuation: .dummy)

        XCTAssertEqual(Set(written), ["/out/a.txt", "/out/b.txt"])
    }
}
```

---

## Test helpers needed (add to TestHelpers/ if not present)

- `NullAuthGate` — an `AuthGate` that always returns `.allow`
- `EngineFactory.make(toolRouter:hooks:)` — creates an `AgenticEngine` with injected router
- `AsyncStream<AgentEvent>.Continuation.dummy` — a no-op continuation for tests

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `dispatchRegularCalls()` does not exist on `AgenticEngine`.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add TestHelpers/MockToolRouter.swift \
        MerlinTests/Unit/AsyncToolDispatchTests.swift
git commit -m "Task 198a — AsyncToolDispatchTests (failing)"
```
