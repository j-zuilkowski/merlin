import Foundation
@testable import Merlin

/// ToolRouter wrapper that replaces every tool result with an empty string.
/// Used to simulate a tool call that succeeds syntactically but returns
/// semantically empty or useless data.
@MainActor
final class EmptyToolResultRouter: ToolRouter {
    override func dispatch(
        _ calls: [ToolCall],
        stagingBufferOverride: StagingBuffer? = nil,
        permissionModeOverride: PermissionMode? = nil
    ) async -> [ToolResult] {
        let results = await super.dispatch(
            calls,
            stagingBufferOverride: stagingBufferOverride,
            permissionModeOverride: permissionModeOverride
        )
        return results.map { result in
            ToolResult(toolCallId: result.toolCallId, content: "", isError: false)
        }
    }
}
