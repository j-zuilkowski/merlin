import XCTest
@testable import Merlin

final class TokenEstimatorTextTests: XCTestCase {

    func testEmptyStringHasBaseCost() {
        XCTAssertEqual(TokenEstimator.estimateText(""), 16)
    }

    func testLongerTextEstimatesHigherThanShortText() {
        let short = TokenEstimator.estimateText("hello")
        let long = TokenEstimator.estimateText(String(repeating: "x", count: 4_000))

        XCTAssertGreaterThanOrEqual(short, 16)
        XCTAssertGreaterThan(long, short)
    }
}
