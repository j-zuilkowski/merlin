import XCTest
@testable import Merlin

final class FindingModelTests: XCTestCase {

    func testFindingCodableRoundTrip() throws {
        let f = Finding(
            id: UUID(),
            category: .phaseDrift,
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
        XCTAssertEqual(decoded.category, .phaseDrift)
        XCTAssertEqual(decoded.severity, .block)
        XCTAssertEqual(decoded.summary, "Symbol missing")
        XCTAssertEqual(decoded.suggestedAction, "Restore or write addendum")
    }

    func testFindingCategoryRawValues() {
        XCTAssertEqual(FindingCategory.phaseDrift.rawValue, "phaseDrift")
        XCTAssertEqual(FindingCategory.manualCoverageGap.rawValue, "manualCoverageGap")
        XCTAssertEqual(FindingCategory.docStaleReference.rawValue, "docStaleReference")
        XCTAssertEqual(FindingCategory.whyCommentMissing.rawValue, "whyCommentMissing")
        XCTAssertEqual(FindingCategory.proseReadabilityFail.rawValue, "proseReadabilityFail")
        XCTAssertEqual(FindingCategory.versionBumpCandidate.rawValue, "versionBumpCandidate")
        XCTAssertEqual(FindingCategory.overrideAuditAccumulation.rawValue, "overrideAuditAccumulation")
    }

    func testSeverityRawValues() {
        XCTAssertEqual(Severity.block.rawValue, "block")
        XCTAssertEqual(Severity.nudge.rawValue, "nudge")
        XCTAssertEqual(Severity.silent.rawValue, "silent")
    }
}
