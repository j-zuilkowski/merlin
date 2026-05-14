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

        let systemMsg = cm.messages.first { $0.role == .system }
        guard let systemMsg else {
            XCTFail("System message must remain after truncation")
            return
        }
        if case .text(let t) = systemMsg.content {
            XCTAssertTrue(t.contains("[truncated"), "Truncated system prompt must contain '[truncated …]' marker")
        } else {
            XCTFail("System message content must be text")
        }
    }

    func testTokensReducedAfterApplyingCaps() async {
        let cm = ContextManager()
        for i in 0..<10 {
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
