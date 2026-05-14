import XCTest
@testable import Merlin

final class ProviderBudgetTests: XCTestCase {

    func testUsableInputTokensSubtractReservedOutputTokens() {
        let budget = ProviderBudget(maxInputTokens: 32_000, reservedOutputTokens: 4_096)
        XCTAssertEqual(budget.usableInputTokens, 27_904)
    }

    func testLegacyConfigCanOmitBudget() {
        let config = ProviderConfig(
            id: "legacy",
            displayName: "Legacy",
            baseURL: "http://localhost",
            model: "test",
            isEnabled: true,
            isLocal: true,
            supportsThinking: false,
            supportsVision: false,
            kind: .openAICompatible
        )

        XCTAssertNil(config.budget)
    }
}
