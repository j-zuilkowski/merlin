import XCTest
@testable import Merlin

@MainActor
final class CompactSlashCommandTests: XCTestCase {

    func test_compactSlashCommandInvokesCompactionAndIsConsumed() {
        var compactionCount = 0
        let handler = SlashCommandHandler(
            onCompact: {
                compactionCount += 1
            },
            onCalibrate: {
                XCTFail("/calibrate should not be invoked for /compact")
            }
        )

        let outcome = handler.handle("/compact")

        XCTAssertEqual(outcome, .consumed)
        XCTAssertEqual(compactionCount, 1)
    }

    func test_compactSlashCommandWithExtraTextStillInvokesCompactionAndIsConsumed() {
        var compactionCount = 0
        let handler = SlashCommandHandler(
            onCompact: {
                compactionCount += 1
            },
            onCalibrate: {
                XCTFail("/calibrate should not be invoked for /compact extra text")
            }
        )

        let outcome = handler.handle("/compact extra text")

        XCTAssertEqual(outcome, .consumed)
        XCTAssertEqual(compactionCount, 1)
    }

    func test_calibrateSlashCommandInvokesInjectedCalibrateAction() {
        var calibrateCount = 0
        let handler = SlashCommandHandler(
            onCompact: {
                XCTFail("/compact should not be invoked for /calibrate")
            },
            onCalibrate: {
                calibrateCount += 1
            }
        )

        let outcome = handler.handle("/calibrate")

        XCTAssertEqual(outcome, .consumed)
        XCTAssertEqual(calibrateCount, 1)
    }

    func test_unknownSlashCommandIsNotHandled() {
        var compactionCount = 0
        var calibrateCount = 0
        let handler = SlashCommandHandler(
            onCompact: {
                compactionCount += 1
            },
            onCalibrate: {
                calibrateCount += 1
            }
        )

        let outcome = handler.handle("/unknown")

        XCTAssertEqual(outcome, .notHandled)
        XCTAssertEqual(compactionCount, 0)
        XCTAssertEqual(calibrateCount, 0)
    }
}
