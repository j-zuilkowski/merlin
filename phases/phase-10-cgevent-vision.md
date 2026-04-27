# Phase 10 — CGEventTool + VisionQueryTool

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 04 complete: LMStudioProvider exists. Phase 09b complete: ScreenCaptureTool exists.

---

## Write to: Merlin/Tools/CGEventTool.swift

```swift
import CoreGraphics

enum CGEventTool {
    static func click(x: Double, y: Double, button: CGMouseButton = .left) throws
    static func doubleClick(x: Double, y: Double) throws
    static func rightClick(x: Double, y: Double) throws
    static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double) throws
    static func typeText(_ text: String) throws
    static func pressKey(_ keyCombo: String) throws  // e.g. "cmd+s", "return", "escape"
    static func scroll(x: Double, y: Double, deltaX: Double, deltaY: Double) throws
}
```

Use `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` and `CGEvent.post(tap:)`. For `typeText`, use `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with Unicode. For `pressKey`, parse modifier+key string into `CGKeyCode` + `CGEventFlags`.
Use this key code table:

```swift
private static let keyCodes: [String: CGKeyCode] = [
    "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
    "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
    "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
    "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "6": 22, "7": 26, "8": 28, "9": 25,
    "[": 33, "]": 30, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
    "`": 50, "-": 27, "=": 24, "\\": 42,
]

private static let modifierFlags: [String: CGEventFlags] = [
    "cmd": .maskCommand, "command": .maskCommand,
    "shift": .maskShift, "opt": .maskAlternate,
    "option": .maskAlternate, "alt": .maskAlternate,
    "ctrl": .maskControl, "control": .maskControl,
]
```

Parse "cmd+s" by splitting on `+`, separating modifier tokens from the key token,
combining flags, then looking up the key code. Throw if key combo is empty or key not found.

---

## Write to: Merlin/Tools/VisionQueryTool.swift

```swift
import Foundation

struct VisionResponse: Codable {
    var x: Int?
    var y: Int?
    var action: String?
    var confidence: Double?
    var description: String?
}

enum VisionQueryTool {
    // Sends JPEG data to LM Studio vision model
    // prompt: plain text instruction, e.g. "Where is the Build button? Return JSON."
    // Returns raw model response string
    static func query(imageData: Data, prompt: String, provider: LMStudioProvider) async throws -> String

    // Convenience: parse JSON from model response into VisionResponse
    static func parseResponse(_ raw: String) -> VisionResponse?
}
```

`query` builds a `CompletionRequest` with:
- `content: .parts([.imageURL("data:image/jpeg;base64,<base64>"), .text(prompt)])`
- `temperature: 0.1`
- `maxTokens: 256`

Collects full streamed response, returns joined string.

---

## Write to: MerlinTests/Unit/CGEventToolTests.swift

```swift
import XCTest
@testable import Merlin

final class CGEventToolTests: XCTestCase {
    func testKeyComboParser() throws {
        // Test parser doesn't throw on valid combos
        XCTAssertNoThrow(try CGEventTool.pressKey("cmd+s"))
        XCTAssertNoThrow(try CGEventTool.pressKey("return"))
        XCTAssertNoThrow(try CGEventTool.pressKey("escape"))
        XCTAssertThrowsError(try CGEventTool.pressKey(""))
    }

    func testVisionResponseParser() {
        let raw = #"{"x": 320, "y": 180, "confidence": 0.92, "action": "click"}"#
        let r = VisionQueryTool.parseResponse(raw)
        XCTAssertEqual(r?.x, 320)
        XCTAssertEqual(r?.confidence, 0.92)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/CGEventToolTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'CGEventToolTests' passed` with 2 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/CGEventTool.swift Merlin/Tools/VisionQueryTool.swift MerlinTests/Unit/CGEventToolTests.swift
git commit -m "Phase 10 — CGEventTool + VisionQueryTool + tests"
```
