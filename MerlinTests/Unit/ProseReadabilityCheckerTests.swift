import XCTest
@testable import Merlin

final class ProseReadabilityCheckerTests: XCTestCase {

    func testDryRunReturnsFinding() async {
        let checker = ProseReadabilityChecker(dryRun: true)
        let finding = await checker.check(docFile: "/tmp/test.md", targetGrade: 9.0)
        XCTAssertEqual(finding.docFile, "/tmp/test.md")
        XCTAssertGreaterThanOrEqual(finding.measuredGrade, 0)
        XCTAssertEqual(finding.targetGrade, 9.0)
    }

    func testAboveTargetProducesSuggestions() async {
        let checker = ProseReadabilityChecker(dryRun: true, forcedGrade: 14.0)
        let finding = await checker.check(docFile: "/tmp/hard.md", targetGrade: 9.0)
        XCTAssertGreaterThan(finding.measuredGrade, finding.targetGrade)
        XCTAssertFalse(finding.suggestions.isEmpty,
                       "Suggestions should be non-empty when grade exceeds target")
    }

    func testAtOrBelowTargetNoSuggestions() async {
        let checker = ProseReadabilityChecker(dryRun: true, forcedGrade: 7.0)
        let finding = await checker.check(docFile: "/tmp/easy.md", targetGrade: 9.0)
        XCTAssertLessThanOrEqual(finding.measuredGrade, finding.targetGrade)
        XCTAssertTrue(finding.suggestions.isEmpty,
                      "No suggestions expected when grade is at or below target")
    }

    func testReadabilityFindingIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        let f = ReadabilityFinding(docFile: "x.md", measuredGrade: 8, targetGrade: 9, suggestions: [])
        requiresSendable(f)
    }
}
