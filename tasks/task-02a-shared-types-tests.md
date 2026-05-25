# Phase 02a — Shared Types: Tests First

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

## Write to: MerlinTests/Unit/SharedTypesTests.swift

Tests must compile but fail (types don't exist yet).

```swift
import XCTest
@testable import Merlin

final class SharedTypesTests: XCTestCase {

    // Message round-trips through JSON
    func testMessageCodable() throws {
        let msg = Message(role: .user, content: .text("hello"), timestamp: Date())
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.role, .user)
        if case .text(let s) = decoded.content { XCTAssertEqual(s, "hello") }
        else { XCTFail("wrong content type") }
    }

    // ToolCall round-trips
    func testToolCallCodable() throws {
        let tc = ToolCall(id: "abc", type: "function",
                          function: FunctionCall(name: "read_file", arguments: #"{"path":"/tmp/f"}"#))
        let data = try JSONEncoder().encode(tc)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(decoded.id, "abc")
        XCTAssertEqual(decoded.function.name, "read_file")
    }

    // Tool result marks errors
    func testToolResultError() {
        let r = ToolResult(toolCallId: "x", content: "boom", isError: true)
        XCTAssertTrue(r.isError)
    }

    // ThinkingConfig encodes correct keys
    func testThinkingConfigEnabled() throws {
        let cfg = ThinkingConfig(type: "enabled", reasoningEffort: "high")
        let data = try JSONEncoder().encode(cfg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "enabled")
        XCTAssertEqual(json["reasoning_effort"] as? String, "high")
    }

    // MessageContent with image part survives encode/decode
    func testImageContentCodable() throws {
        let part = ContentPart.imageURL("data:image/jpeg;base64,abc123")
        let msg = Message(role: .user, content: .parts([part, .text("what is this?")]), timestamp: Date())
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        if case .parts(let parts) = decoded.content {
            XCTAssertEqual(parts.count, 2)
        } else { XCTFail() }
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing types — that is correct for a test-first phase.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: build errors referencing `Message`, `ToolCall`, etc. — not logic errors. `BUILD FAILED` is correct here.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SharedTypesTests.swift
git commit -m "Phase 02a — SharedTypesTests (failing, types not yet defined)"
```
