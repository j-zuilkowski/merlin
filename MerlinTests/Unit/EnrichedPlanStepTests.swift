import XCTest
@testable import Merlin

final class EnrichedPlanStepTests: XCTestCase {

    func testMissingFieldsDecodeWithExpectedDefaults() throws {
        let data = #"{ "description": "Ship it", "successCriteria": ["done"], "complexity": "standard" }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PlanStep.self, from: data)

        XCTAssertEqual(decoded.tokenBudget, 0)
        XCTAssertEqual(decoded.minContextRequired, 0)
        XCTAssertEqual(decoded.requiresCritic, .optional)
    }

    func testSerializationRetainsStructuredFields() throws {
        let step = PlanStep(
            description: "Split the migration",
            successCriteria: [.prose("migration lands"), .buildSucceeds],
            complexity: .highStakes,
            parallelSafe: true,
            tokenBudget: 48_000,
            requiresCritic: .required,
            minContextRequired: 64_000
        )

        let data = try JSONEncoder().encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["description"] as? String, "Split the migration")
        XCTAssertEqual(json?["parallelSafe"] as? Bool, true)
        XCTAssertEqual(json?["tokenBudget"] as? Int, 48_000)
        XCTAssertEqual(json?["requiresCritic"] as? String, "required")
        XCTAssertEqual(json?["minContextRequired"] as? Int, 64_000)
    }
}
