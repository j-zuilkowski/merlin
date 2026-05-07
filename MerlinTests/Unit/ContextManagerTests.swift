import XCTest
@testable import Merlin

@MainActor
final class ContextManagerTests: XCTestCase {

    func testTokenEstimate() {
        let cm = ContextManager()
        let msg = Message(role: .user, content: .text(String(repeating: "a", count: 350)), timestamp: Date())
        cm.append(msg)
        XCTAssertEqual(cm.estimatedTokens, 100, accuracy: 5)
    }

    func testAppendAndRetrieve() {
        let cm = ContextManager()
        let m1 = Message(role: .user, content: .text("hello"), timestamp: Date())
        let m2 = Message(role: .assistant, content: .text("hi"), timestamp: Date())
        cm.append(m1)
        cm.append(m2)
        XCTAssertEqual(cm.messages.count, 2)
    }

    func testCompactionFiresAt800k() {
        // Use proper exchange pairs (assistant tool_call + tool result) so the
        // new compact logic can find and remove them as complete groups.
        let cm = ContextManager()
        for i in 0..<100 {
            let call = ToolCall(id: "tc\(i)", type: "function",
                                function: FunctionCall(name: "f", arguments: "{}"))
            let asst = Message(role: .assistant, content: .text(""),
                               toolCalls: [call], timestamp: Date())
            let tool = Message(role: .tool,
                               content: .text(String(repeating: "x", count: 28_000)),
                               toolCallId: "tc\(i)", timestamp: Date())
            cm.append(asst)
            cm.append(tool)
        }
        XCTAssertLessThan(cm.estimatedTokens, 800_000)
    }

    func testCompactionPreservesUserAssistantMessages() {
        let cm = ContextManager()
        let user = Message(role: .user, content: .text("important question"), timestamp: Date())
        let asst = Message(role: .assistant, content: .text("important answer"), timestamp: Date())
        cm.append(user)
        cm.append(asst)
        // Use exchange pairs so the new compact logic can remove them.
        for i in 0..<100 {
            let call = ToolCall(id: "tc\(i)", type: "function",
                                function: FunctionCall(name: "f", arguments: "{}"))
            let asstTool = Message(role: .assistant, content: .text(""),
                                   toolCalls: [call], timestamp: Date())
            let toolResult = Message(role: .tool,
                                     content: .text(String(repeating: "y", count: 28_000)),
                                     toolCallId: "tc\(i)", timestamp: Date())
            cm.append(asstTool)
            cm.append(toolResult)
        }
        XCTAssertTrue(cm.messages.contains { $0.role == .user })
        XCTAssertTrue(cm.messages.contains { $0.role == .assistant && $0.toolCalls == nil })
    }

    func testClearResetsState() {
        let cm = ContextManager()
        cm.append(Message(role: .user, content: .text("hi"), timestamp: Date()))
        cm.clear()
        XCTAssertTrue(cm.messages.isEmpty)
        XCTAssertEqual(cm.estimatedTokens, 0)
    }
}
