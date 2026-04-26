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
