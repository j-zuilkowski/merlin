import Foundation

enum SubagentEvent: @unchecked Sendable {
    case toolCallStarted(toolName: String, input: [String: String])
    case toolCallCompleted(toolName: String, result: String)
    case messageChunk(String)
    case completed(summary: String)
    case failed(any Error)
}
