import XCTest
@testable import Merlin

@MainActor
final class RewindSlashCommandTests: XCTestCase {

    func test_rewind_parses_no_argument_as_stepsBack_1() {
        let (steps, valid) = RewindCommand.parse("/rewind")
        XCTAssertTrue(valid)
        XCTAssertEqual(steps, 1)
    }

    func test_rewind_parses_numeric_argument() {
        let (steps, valid) = RewindCommand.parse("/rewind 3")
        XCTAssertTrue(valid)
        XCTAssertEqual(steps, 3)
    }

    func test_rewind_rejects_non_numeric_argument() {
        let (_, valid) = RewindCommand.parse("/rewind foo")
        XCTAssertFalse(valid)
    }

    func test_rewind_rejects_zero_or_negative() {
        XCTAssertFalse(RewindCommand.parse("/rewind 0").valid)
        XCTAssertFalse(RewindCommand.parse("/rewind -1").valid)
    }

    func test_non_rewind_command_returns_invalid() {
        let (_, valid) = RewindCommand.parse("/compact")
        XCTAssertFalse(valid)
    }
}
