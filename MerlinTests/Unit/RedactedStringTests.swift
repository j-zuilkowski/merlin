import XCTest
@testable import Merlin

final class RedactedStringTests: XCTestCase {

    func testRedactedStripsTokenShapedSubstrings() {
        let input = "prefix sk-ABC12345 middle pk-xyz_9876 suffix Bearer abc.def-ghi"
        let output = RedactedString.redacted(input)
        XCTAssertFalse(output.contains("sk-ABC12345"))
        XCTAssertFalse(output.contains("pk-xyz_9876"))
        XCTAssertFalse(output.contains("Bearer abc.def-ghi"))
        XCTAssertTrue(output.contains("prefix"))
        XCTAssertTrue(output.contains("middle"))
        XCTAssertTrue(output.contains("suffix"))
    }

    func testRedactedTrimsToFiveHundredCharacters() {
        let longInput = String(repeating: "a", count: 520)
        let output = RedactedString.redacted(longInput)
        XCTAssertLessThanOrEqual(output.count, 500)
    }

    func testRedactedLeavesOrdinaryTextUnchanged() {
        let input = "ordinary text without secrets"
        let output = RedactedString.redacted(input)
        XCTAssertEqual(output, input)
    }
}
