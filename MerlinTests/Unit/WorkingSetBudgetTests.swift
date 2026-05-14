import XCTest
@testable import Merlin

final class WorkingSetBudgetTests: XCTestCase {

    func testDeriveFromBudgetTotalDoesNotExceedUsableInputTokens() {
        let budget = ProviderBudget(maxInputTokens: 32_000, reservedOutputTokens: 4_096)
        let caps = WorkingSetBudget.derive(from: budget)
        XCTAssertLessThanOrEqual(caps.total, budget.usableInputTokens)
    }

    func testDeriveRatiosForRoundBudget() {
        let budget = ProviderBudget(maxInputTokens: 100_000, reservedOutputTokens: 0)
        let caps = WorkingSetBudget.derive(from: budget)
        XCTAssertEqual(caps.systemPromptCap, 10_000)
        XCTAssertEqual(caps.ragInjectionCap, 25_000)
        XCTAssertEqual(caps.recentTurnsCap, 50_000)
        XCTAssertEqual(caps.toolBurstCap, 15_000)
    }

    func testSmallBudgetClampsEachCapToMinimumFloor() {
        let budget = ProviderBudget(maxInputTokens: 500, reservedOutputTokens: 0)
        let caps = WorkingSetBudget.derive(from: budget)
        XCTAssertGreaterThanOrEqual(caps.systemPromptCap, 256)
        XCTAssertGreaterThanOrEqual(caps.ragInjectionCap, 256)
        XCTAssertGreaterThanOrEqual(caps.recentTurnsCap, 256)
        XCTAssertGreaterThanOrEqual(caps.toolBurstCap, 256)
    }

    func testTotalComputedPropertySumsComponents() {
        let caps = WorkingSetBudget(
            systemPromptCap: 1_000,
            ragInjectionCap: 2_500,
            recentTurnsCap: 5_000,
            toolBurstCap: 1_500
        )
        XCTAssertEqual(caps.total, 10_000)
    }
}
