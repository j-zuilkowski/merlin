# Phase 14a — ContextManager Tests

Context: HANDOFF.md. Message type exists. Write failing tests only.

## Write to: MerlinTests/Unit/ContextManagerTests.swift

```swift
import XCTest
@testable import Merlin

final class ContextManagerTests: XCTestCase {

    func testTokenEstimate() {
        let cm = ContextManager()
        let msg = Message(role: .user, content: .text(String(repeating: "a", count: 350)), timestamp: Date())
        cm.append(msg)
        // 350 chars ÷ 3.5 = 100 tokens
        XCTAssertEqual(cm.estimatedTokens, 100, accuracy: 5)
    }

    func testAppendAndRetrieve() {
        let cm = ContextManager()
        let m1 = Message(role: .user, content: .text("hello"), timestamp: Date())
        let m2 = Message(role: .assistant, content: .text("hi"), timestamp: Date())
        cm.append(m1); cm.append(m2)
        XCTAssertEqual(cm.messages.count, 2)
    }

    func testCompactionFiresAt800k() {
        let cm = ContextManager()
        // Add enough tool result messages to exceed threshold
        for _ in 0..<100 {
            let toolMsg = Message(role: .tool, content: .text(String(repeating: "x", count: 28_000)),
                                  toolCallId: "tc1", timestamp: Date())
            cm.append(toolMsg)
        }
        // Should have compacted — total tokens should be below 800k
        XCTAssertLessThan(cm.estimatedTokens, 800_000)
    }

    func testCompactionPreservesUserAssistantMessages() {
        let cm = ContextManager()
        let user = Message(role: .user, content: .text("important question"), timestamp: Date())
        let asst = Message(role: .assistant, content: .text("important answer"), timestamp: Date())
        cm.append(user); cm.append(asst)
        // Pad with tool messages to trigger compaction
        for _ in 0..<100 {
            cm.append(Message(role: .tool, content: .text(String(repeating: "y", count: 28_000)),
                              toolCallId: "t", timestamp: Date()))
        }
        XCTAssertTrue(cm.messages.contains { $0.role == .user })
        XCTAssertTrue(cm.messages.contains { $0.role == .assistant })
    }

    func testClearResetsState() {
        let cm = ContextManager()
        cm.append(Message(role: .user, content: .text("hi"), timestamp: Date()))
        cm.clear()
        XCTAssertTrue(cm.messages.isEmpty)
        XCTAssertEqual(cm.estimatedTokens, 0)
    }
}
```

## Acceptance
- [ ] Compiles (types missing — expected)
