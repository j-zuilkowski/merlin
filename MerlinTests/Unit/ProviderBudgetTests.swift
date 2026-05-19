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

    // MARK: - preflightSafe

    func testPreflightSafeKeepsAValidBudget() {
        let valid = ProviderBudget(maxInputTokens: 128_000, reservedOutputTokens: 8_192)
        XCTAssertEqual(valid.preflightSafe, valid)
    }

    func testPreflightSafeReplacesAZeroBudget() {
        // maxInputTokens == reservedOutputTokens → usableInputTokens 0.
        let degenerate = ProviderBudget(maxInputTokens: 4_096, reservedOutputTokens: 4_096)
        XCTAssertEqual(degenerate.usableInputTokens, 0)
        XCTAssertEqual(degenerate.preflightSafe, .conservative,
                       "a zero-usable budget must fall back to .conservative")
    }

    func testPreflightSafeReplacesANegativeBudget() {
        // reservedOutputTokens > maxInputTokens → usableInputTokens negative.
        let degenerate = ProviderBudget(maxInputTokens: 1_000, reservedOutputTokens: 4_096)
        XCTAssertLessThan(degenerate.usableInputTokens, 0)
        XCTAssertEqual(degenerate.preflightSafe, .conservative)
    }
}
