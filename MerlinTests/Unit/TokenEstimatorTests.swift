import Foundation
import XCTest
@testable import Merlin

final class TokenEstimatorTests: XCTestCase {

    private func makeRequest(message: String) -> CompletionRequest {
        CompletionRequest(
            model: "test-model",
            messages: [
                Message(role: .user, content: .text(message), timestamp: Date())
            ]
        )
    }

    func testEstimateGrowsWithMessageSize() {
        let short = TokenEstimator.estimate(request: makeRequest(message: "hi"))
        let long = TokenEstimator.estimate(request: makeRequest(message: String(repeating: "x", count: 4_000)))

        XCTAssertGreaterThan(long, short)
    }

    func testEstimateIncludesHeadroomAndFloor() throws {
        let request = makeRequest(message: "hello")
        let encoded = try encodeRequest(
            request,
            baseURL: URL(string: "http://localhost")!,
            model: request.model
        )
        let estimate = TokenEstimator.estimate(request: request)

        XCTAssertGreaterThanOrEqual(estimate, Int(ceil(Double(encoded.count) / 4.0)))
        XCTAssertGreaterThanOrEqual(estimate, 512)
    }
}
