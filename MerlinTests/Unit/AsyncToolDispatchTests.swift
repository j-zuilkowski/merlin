// AsyncToolDispatchTests.swift
// Task 198a — batch tool dispatch via dispatchRegularCalls.
import XCTest
@testable import Merlin

@MainActor
final class AsyncToolDispatchTests: XCTestCase {

    // MARK: - Helpers

    private func makeDummyContinuation() -> AsyncStream<AgentEvent>.Continuation {
        AsyncStream<AgentEvent>.makeStream().continuation
    }

    // MARK: - Batch dispatch

    /// When a single streaming response contains N regular tool calls, dispatch() must be
    /// called exactly ONCE with all N calls — not N times with one call each.
    func test_multipleToolCalls_areDispatchedInOneBatch() async throws {
        let router = MockToolRouter(authGate: NullAuthGate())
        let engine = EngineFactory.make(toolRouter: router)

        let calls = (1...3).map { i in
            ToolCall(id: "id-\(i)", type: "function",
                     function: FunctionCall(name: "read_file", arguments: #"{"path":"/tmp/f\#(i)"}"#))
        }

        var written: [String] = []
        await engine.dispatchRegularCalls(calls, turn: 1, loopCount: 0,
                                          writtenFilePaths: &written, continuation: makeDummyContinuation())

        XCTAssertEqual(router.dispatchRecords.count, 1,
                       "dispatch() must be called once with all calls, not per-call")
        XCTAssertEqual(router.dispatchRecords.first?.calls.count, 3)
    }

    /// Calls denied by PreToolUse hooks must NOT appear in the dispatch batch.
    /// Uses a shell hook that inspects the tool name from stdin JSON.
    func test_hookedDenialIsExcludedFromBatch() async throws {
        let router = MockToolRouter(authGate: NullAuthGate())
        let engine = EngineFactory.make(toolRouter: router)

        // Shell hook: deny write_file, allow everything else.
        // HookEngine passes {"tool":"<name>",...} as stdin JSON; the hook reads it and decides.
        let denyWriteFile = HookConfig(
            event: "PreToolUse",
            command: #"grep -q '"write_file"' && printf '{"decision":"deny"}' || printf '{"decision":"allow"}'"#
        )
        let saved = AppSettings.shared.hooks
        AppSettings.shared.hooks = [denyWriteFile]
        defer { AppSettings.shared.hooks = saved }

        let calls = [
            ToolCall(id: "a", type: "function",
                     function: FunctionCall(name: "write_file", arguments: #"{"path":"/tmp/x"}"#)),
            ToolCall(id: "b", type: "function",
                     function: FunctionCall(name: "read_file", arguments: #"{"path":"/tmp/y"}"#))
        ]

        var written: [String] = []
        await engine.dispatchRegularCalls(calls, turn: 1, loopCount: 0,
                                          writtenFilePaths: &written, continuation: makeDummyContinuation())

        XCTAssertEqual(router.dispatchRecords.count, 1,
                       "dispatch() should still be called once with the allowed calls")
        XCTAssertEqual(router.dispatchRecords.first?.calls.count, 1,
                       "only the allowed read_file call should reach the router")
        XCTAssertEqual(router.dispatchRecords.first?.calls.first?.id, "b")
    }

    /// Results must be appended to context in original call order, regardless of
    /// parallel execution order inside the router.
    func test_resultsAreAppliedInOriginalCallOrder() async throws {
        let router = MockToolRouter(authGate: NullAuthGate())
        // Return results in reverse order to test that ordering is corrected.
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
                                          writtenFilePaths: &written, continuation: makeDummyContinuation())

        // Tool result messages appended to context must be x, y, z in that order.
        let toolMessages = engine.contextManager.messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.compactMap { $0.toolCallId }, ["x", "y", "z"])
    }

    /// write_file paths must still be tracked even when dispatched in a batch.
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
                                          writtenFilePaths: &written, continuation: makeDummyContinuation())

        XCTAssertEqual(Set(written), ["/out/a.txt", "/out/b.txt"])
    }
}
