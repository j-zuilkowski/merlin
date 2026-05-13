import XCTest
@testable import Merlin

@MainActor
final class ContextPreRunCompactionTests: XCTestCase {

    // MARK: - preRunCompactionThreshold

    func testDefaultThresholdIs10000() {
        let cm = ContextManager()
        XCTAssertEqual(cm.preRunCompactionThreshold, 10_000)
    }

    // MARK: - compactIfNeededBeforeRun

    func testDoesNotCompactWhenUnderThreshold() {
        let cm = ContextManager()
        // Add a few small tool messages — well under 10 000 tokens
        for i in 0..<5 {
            cm.append(Message(
                role: .tool,
                content: .text("result \(i)"),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertLessThan(cm.estimatedTokens, cm.preRunCompactionThreshold)
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertEqual(cm.compactionCount, 0)
    }

    func testCompactsWhenOverThreshold() {
        let cm = ContextManager()
        // Each "x" * 3 500 is ~1 000 tokens; add 12 → ~12 000 tokens (> 10 000)
        for i in 0..<12 {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "x", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertGreaterThan(cm.estimatedTokens, cm.preRunCompactionThreshold)
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertEqual(cm.compactionCount, 1)
    }

    func testSkipsCompactionForContinuationTurns() {
        let cm = ContextManager()
        for i in 0..<12 {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "x", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertGreaterThan(cm.estimatedTokens, cm.preRunCompactionThreshold)
        cm.compactIfNeededBeforeRun(isContinuation: true)
        XCTAssertEqual(cm.compactionCount, 0)
    }

    func testTokensReducedAfterPreRunCompaction() {
        let cm = ContextManager()
        // Use 25 messages so that hard-truncation (keeps last 20) actually removes some.
        for i in 0..<25 {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "x", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        let tokensBefore = cm.estimatedTokens
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertLessThan(cm.estimatedTokens, tokensBefore)
    }

    func testUserAndAssistantMessagesPreservedAfterPreRunCompaction() {
        let cm = ContextManager()
        cm.append(Message(role: .user, content: .text("plan this"), timestamp: Date()))
        cm.append(Message(role: .assistant, content: .text("here is the plan"), timestamp: Date()))
        for i in 0..<12 {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "y", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
        cm.compactIfNeededBeforeRun(isContinuation: false)
        XCTAssertTrue(cm.messages.contains { $0.role == .user })
        XCTAssertTrue(cm.messages.contains { $0.role == .assistant })
    }
}
