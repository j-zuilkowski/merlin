import Foundation
@testable import Merlin

/// ToolRouter wrapper that replaces every tool result with an empty string.
/// Used to simulate a tool call that succeeds syntactically but returns
/// semantically empty or useless data.
@MainActor
final class EmptyToolResultRouter: ToolRouter {
    override func dispatch(_ calls: [ToolCall]) async -> [ToolResult] {
        let results = await super.dispatch(calls)
        return results.map { result in
            ToolResult(toolCallId: result.toolCallId, content: "", isError: false)
        }
    }
}
