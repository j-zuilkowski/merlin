import Foundation

/// One tool invocation inside a subagent block.
struct SubagentToolLine: Sendable, Equatable {
    let name: String
    let done: Bool
}

/// A value snapshot of a subagent's state, carried on a `ChatEntry` so the pure
/// `ConversationHTMLRenderer` can render it without reading a view model.
struct SubagentBlock: Sendable, Equatable {
    var agentName: String
    var status: String          // "running" | "completed" | "failed"
    var tools: [SubagentToolLine]
    var summary: String?
    var text: String
}
