// MockToolRouter.swift
// Phase 198a — records how dispatch() is called for inspection in tests.
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

    override func dispatch(
        _ calls: [ToolCall],
        stagingBufferOverride: StagingBuffer? = nil,
        permissionModeOverride: PermissionMode? = nil
    ) async -> [ToolResult] {
        dispatchRecords.append(DispatchRecord(calls: calls, timestamp: Date()))
        return resultFactory(calls)
    }
}
