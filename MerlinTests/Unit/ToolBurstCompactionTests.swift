import XCTest
@testable import Merlin

@MainActor
final class ToolBurstCompactionTests: XCTestCase {

    private func appendToolExchanges(_ cm: ContextManager, count: Int, size: Int = 3_500) {
        for i in 0..<count {
            let call = ToolCall(id: "tc\(i)", type: "function",
                                function: FunctionCall(name: "read_file", arguments: "{}"))
            cm.append(Message(role: .assistant, content: .text(""),
                              toolCalls: [call], timestamp: Date()))
            cm.append(Message(role: .tool,
                              content: .text(String(repeating: "x", count: size)),
                              toolCallId: "tc\(i)", timestamp: Date()))
        }
    }

    func testCompactAfterToolBurstReducesTokensByAtLeast30Percent() {
        let cm = ContextManager()
        appendToolExchanges(cm, count: 10)
        let before = cm.estimatedTokens

        cm.compactAfterToolBurst()

        let reduction = Double(before - cm.estimatedTokens) / Double(before)
        XCTAssertGreaterThanOrEqual(reduction, 0.30,
                                    "Tool-burst compaction must reduce tokens by at least 30%")
    }

    func testCompactAfterToolBurstIsNoOpWhenBelowCap() {
        let cm = ContextManager()
        // Single small exchange — well below any reasonable cap
        appendToolExchanges(cm, count: 1, size: 100)
        let before = cm.estimatedTokens

        cm.compactAfterToolBurst()

        XCTAssertEqual(cm.estimatedTokens, before,
                       "Must not compact when tool-burst component is within cap")
    }

    func testCompactAfterToolBurstIncrementsCompactionCount() {
        let cm = ContextManager()
        appendToolExchanges(cm, count: 10)

        cm.compactAfterToolBurst()

        XCTAssertEqual(cm.compactionCount, 1)
    }
}
