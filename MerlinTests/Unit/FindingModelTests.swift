import XCTest
@testable import Merlin

final class FindingModelTests: XCTestCase {

    func testFindingCodableRoundTrip() throws {
        let f = Finding(
            id: UUID(),
            category: .taskDrift,
            severity: .block,
            summary: "Symbol missing",
            detail: "ProviderBudget absent from source",
            suggestedAction: "Restore or write addendum",
            createdAt: Date(timeIntervalSince1970: 1000),
            lastSeenAt: Date(timeIntervalSince1970: 2000)
        )
        let data = try JSONEncoder().encode(f)
        let decoded = try JSONDecoder().decode(Finding.self, from: data)
        XCTAssertEqual(decoded.id, f.id)
        XCTAssertEqual(decoded.category, .taskDrift)
        XCTAssertEqual(decoded.severity, .block)
        XCTAssertEqual(decoded.summary, "Symbol missing")
        XCTAssertEqual(decoded.suggestedAction, "Restore or write addendum")
    }

    func testFindingCategoryRawValues() {
        XCTAssertEqual(FindingCategory.taskDrift.rawValue, "taskDrift")
        XCTAssertEqual(FindingCategory.manualCoverageGap.rawValue, "manualCoverageGap")
        XCTAssertEqual(FindingCategory.docStaleReference.rawValue, "docStaleReference")
        XCTAssertEqual(FindingCategory.whyCommentMissing.rawValue, "whyCommentMissing")
        XCTAssertEqual(FindingCategory.proseReadabilityFail.rawValue, "proseReadabilityFail")
        XCTAssertEqual(FindingCategory.overrideAuditAccumulation.rawValue, "overrideAuditAccumulation")
        XCTAssertEqual(FindingCategory.ungatedTarget.rawValue, "ungatedTarget")
        XCTAssertEqual(FindingCategory.stubbedImplementation.rawValue, "stubbedImplementation")
        XCTAssertEqual(FindingCategory.unwiredComponent.rawValue, "unwiredComponent")
    }

    func testSeverityRawValues() {
        XCTAssertEqual(Severity.block.rawValue, "block")
        XCTAssertEqual(Severity.nudge.rawValue, "nudge")
        XCTAssertEqual(Severity.silent.rawValue, "silent")
    }
}
