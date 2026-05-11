// AsyncToolDispatchTests.swift
// Phase 198a — failing tests for batch tool dispatch.
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
