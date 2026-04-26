# Phase 16 — ThinkingModeDetector

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 02b complete: ThinkingConfig type exists in Merlin/Providers/LLMProvider.swift.

---

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

Implementation note: use `NSRegularExpression` with `\b<word>\b` pattern (case-insensitive) for whole-word matching. Check OFF words first; if any match, return false immediately without checking ON words.

---

## Write to: MerlinTests/Unit/ThinkingModeDetectorTests.swift

```swift
import XCTest
@testable import Merlin

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

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ThinkingModeDetectorTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'ThinkingModeDetectorTests' passed` with 6 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ThinkingModeDetector.swift MerlinTests/Unit/ThinkingModeDetectorTests.swift
git commit -m "Phase 16 — ThinkingModeDetector + tests (6 tests passing)"
```
