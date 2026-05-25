# Phase 14a — ContextManager Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 02b complete: Message type exists in Merlin/Providers/LLMProvider.swift.

---

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

---

## Verify

Run after writing the file. Expect build errors for missing `ContextManager`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `ContextManager`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ContextManagerTests.swift
git commit -m "Phase 14a — ContextManagerTests (failing)"
```
