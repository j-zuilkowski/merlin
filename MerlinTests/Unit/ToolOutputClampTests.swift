import XCTest
@testable import Merlin

final class ToolOutputClampTests: XCTestCase {

    func testShortOutputIsUnchanged() {
        let text = "the quick brown fox"
        XCTAssertEqual(ToolOutput.clamp(text), text)
    }

    func testEmptyOutputIsUnchanged() {
        XCTAssertEqual(ToolOutput.clamp(""), "")
    }

    func testOutputExactlyAtCapIsUnchanged() {
        let text = String(repeating: "x", count: 200)
        XCTAssertEqual(ToolOutput.clamp(text, maxChars: 200), text)
    }

    func testOversizedOutputIsClampedAndBounded() {
        let text = String(repeating: "x", count: 5_000)
        let clamped = ToolOutput.clamp(text, maxChars: 1_000)
        XCTAssertLessThan(clamped.count, text.count,
                          "oversized output must be shortened")
        // Allow headroom for the elision marker itself.
        XCTAssertLessThan(clamped.count, 1_500,
                          "clamped output must be bounded near maxChars")
    }

    func testClampedOutputCarriesElisionMarker() {
        let text = String(repeating: "x", count: 5_000)
        let clamped = ToolOutput.clamp(text, maxChars: 1_000)
        XCTAssertTrue(clamped.lowercased().contains("elided"),
                      "clamped output must state that content was elided")
    }

    func testClampedOutputKeepsHeadAndTail() {
        let head = String(repeating: "H", count: 100)
        let middle = String(repeating: "m", count: 5_000)
        let tail = String(repeating: "T", count: 100)
        let text = head + middle + tail
        let clamped = ToolOutput.clamp(text, maxChars: 1_000)
        XCTAssertTrue(clamped.hasPrefix(head),
                      "the original head must be preserved")
        XCTAssertTrue(clamped.hasSuffix(tail),
                      "the original tail must be preserved")
    }
}
