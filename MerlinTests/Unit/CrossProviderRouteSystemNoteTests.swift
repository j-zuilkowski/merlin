import XCTest
@testable import Merlin

@MainActor
final class CrossProviderRouteSystemNoteTests: XCTestCase {

    func testRouteDecisionWillAnnounceTheProviderSwitch() {
        let decision: EscalationDecision = .routeToProvider(
            providerID: "big-model",
            reason: "step requires a larger context window"
        )

        switch decision {
        case .routeToProvider(let providerID, let reason):
            XCTAssertEqual(providerID, "big-model")
            XCTAssertTrue(reason.contains("larger context"))
            XCTAssertTrue("Step too large for current model; switching to \(providerID)".contains("switching to \(providerID)"))
        case .continueWith(let replacementSteps):
            XCTFail("Expected provider routing, got steps: \(replacementSteps)")
        case .stop(let message):
            XCTFail("Expected provider routing, got stop: \(message)")
        }
    }
}
