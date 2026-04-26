# Phase 16 — ThinkingModeDetector

Context: HANDOFF.md.

## Write to: Merlin/Engine/ThinkingModeDetector.swift

```swift
import Foundation

enum ThinkingModeDetector {

    // Returns true if the message content contains signal words that warrant thinking mode
    // Signal ON:  debug, why, architecture, design, explain, error, failing, unexpected, broken, investigate
    // Signal OFF: read, write, run, list, build, open, create, delete, move, show
    // OFF signals take precedence over ON signals
    // Case-insensitive whole-word match
    static func shouldEnableThinking(for message: String) -> Bool

    // Builds a ThinkingConfig based on detection result
    // enabled → ThinkingConfig(type: "enabled", reasoningEffort: "high")
    // disabled → ThinkingConfig(type: "disabled", reasoningEffort: nil)
    static func config(for message: String) -> ThinkingConfig
}
```

## Write to: MerlinTests/Unit/ThinkingModeDetectorTests.swift

```swift
final class ThinkingModeDetectorTests: XCTestCase {

    func testDebugEnablesThinking() {
        XCTAssertTrue(ThinkingModeDetector.shouldEnableThinking(for: "can you debug this crash?"))
    }

    func testWhyEnablesThinking() {
        XCTAssertTrue(ThinkingModeDetector.shouldEnableThinking(for: "why is this failing?"))
    }

    func testReadDisablesThinking() {
        XCTAssertFalse(ThinkingModeDetector.shouldEnableThinking(for: "read the file at /tmp/foo.txt"))
    }

    func testOffTakesPrecedence() {
        // "run" (off) + "debug" (on) → off wins
        XCTAssertFalse(ThinkingModeDetector.shouldEnableThinking(for: "run the debug build"))
    }

    func testNeutralMessageDefaultsOff() {
        XCTAssertFalse(ThinkingModeDetector.shouldEnableThinking(for: "hello there"))
    }

    func testConfigReturnsCorrectStruct() {
        let cfg = ThinkingModeDetector.config(for: "investigate this crash")
        XCTAssertEqual(cfg.type, "enabled")
        XCTAssertEqual(cfg.reasoningEffort, "high")
    }
}
```

## Acceptance
- [ ] `swift test --filter ThinkingModeDetectorTests` — all 6 pass
- [ ] `swift build` — zero errors
