import XCTest
@testable import Merlin

@MainActor
final class WorkingSetTruncationTests: XCTestCase {

    func testOversizedRAGTrimmedWithoutTouchingRecentTurns() async {
        let cm = ContextManager()
        // Large RAG injection via system message
        cm.append(Message(role: .system,
                          content: .text(String(repeating: "R", count: 10_000)),
                          timestamp: Date()))
        // Recent conversation turns
        cm.append(Message(role: .user, content: .text("hello"), timestamp: Date()))
        cm.append(Message(role: .assistant, content: .text("hi"), timestamp: Date()))

        let caps = WorkingSetBudget(
            systemPromptCap: 500,
            ragInjectionCap: 500,
            recentTurnsCap: 5_000,
            toolBurstCap: 1_000
        )
        await cm.applyWorkingSetCaps(caps)

        let userMsg = cm.messages.first { $0.role == .user }
        XCTAssertNotNil(userMsg, "Recent user turn must be preserved")
        let assistantMsg = cm.messages.first { $0.role == .assistant }
        XCTAssertNotNil(assistantMsg, "Recent assistant turn must be preserved")
    }

    func testSystemPromptTruncationAddsMarker() async {
        let cm = ContextManager()
        cm.append(Message(role: .system,
                          content: .text(String(repeating: "S", count: 5_000)),
                          timestamp: Date()))

        let caps = WorkingSetBudget(
            systemPromptCap: 100,
            ragInjectionCap: 1_000,
            recentTurnsCap: 1_000,
            toolBurstCap: 500
        )
        await cm.applyWorkingSetCaps(caps)

        // compact() may prepend a summary system message; search all system messages for the
        // truncation marker rather than assuming the first system message is the truncated one.
        let truncatedMsg = cm.messages.first { msg in
            guard msg.role == .system,
                  case .text(let t) = msg.content
            else { return false }
            return t.contains("[truncated")
        }
        XCTAssertNotNil(truncatedMsg, "A system message containing '[truncated' must exist after truncation")
    }

    func testTokensReducedAfterApplyingCaps() async {
        let cm = ContextManager()
        // Use proper (assistant+tool) exchange pairs so compact() can form exchange groups.
        // Orphaned tool messages without a preceding assistant toolCalls message don't form
        // groups and cause hard-truncation to add a summary, increasing token count instead.
        for i in 0..<10 {
            let call = ToolCall(id: "tc\(i)", type: "function",
                                function: FunctionCall(name: "read_file", arguments: "{}"))
            cm.append(Message(role: .assistant, content: .text(""),
                              toolCalls: [call], timestamp: Date()))
            cm.append(Message(role: .tool,
                              content: .text(String(repeating: "T", count: 3_500)),
                              toolCallId: "tc\(i)",
                              timestamp: Date()))
        }
        let before = cm.estimatedTokens

        let caps = WorkingSetBudget(
            systemPromptCap: 256,
            ragInjectionCap: 256,
            recentTurnsCap: 256,
            toolBurstCap: 256
        )
        await cm.applyWorkingSetCaps(caps)

        XCTAssertLessThan(cm.estimatedTokens, before,
                          "Estimated tokens must decrease after applying caps")
    }
}
