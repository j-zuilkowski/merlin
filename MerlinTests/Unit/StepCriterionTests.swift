import XCTest
@testable import Merlin

final class StepCriterionTests: XCTestCase {

    func testCodableRoundTripForEachCase() throws {
        let cases: [StepCriterion] = [
            .prose("build the thing"),
            .buildSucceeds,
            .testsPass(scheme: nil),
            .testsPass(scheme: "MerlinTests"),
            .fileExists(path: "/tmp/output.txt"),
            .regexMatch(pattern: #"error: .*"#, in: .stdout),
            .regexMatch(pattern: #"done"#, in: .file),
            .shellExitZero(command: "swift test")
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for criterion in cases {
            let data = try encoder.encode(criterion)
            let decoded = try decoder.decode(StepCriterion.self, from: data)
            XCTAssertEqual(decoded, criterion)
        }
    }

    func testLegacyStringDecodeWrapsInProseCriterion() throws {
        let data = #"{ "description": "Add feature", "successCriteria": "build the thing", "complexity": "routine" }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PlanStep.self, from: data)

        XCTAssertEqual(decoded.successCriteria, [.prose("build the thing")])
    }
}
