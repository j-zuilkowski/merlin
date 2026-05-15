import XCTest
@testable import Merlin

/// Verifies the live-environment test gate behaves deterministically. These tests must
/// themselves be CI-safe, so they assert the not-live branch.
final class CITestGateTests: XCTestCase {

    func testIsLiveEnvironmentFalseWithoutOptIn() throws {
        if ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" {
            throw XCTSkip("RUN_LIVE_TESTS is set in this environment")
        }
        XCTAssertFalse(isLiveEnvironment(),
                       "isLiveEnvironment() must be false when RUN_LIVE_TESTS is unset")
    }

    func testSkipUnlessLiveEnvironmentThrowsWithoutOptIn() throws {
        if ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" {
            throw XCTSkip("RUN_LIVE_TESTS is set in this environment")
        }
        XCTAssertThrowsError(try skipUnlessLiveEnvironment(),
                             "skipUnlessLiveEnvironment() must throw when not in a live environment")
    }
}
