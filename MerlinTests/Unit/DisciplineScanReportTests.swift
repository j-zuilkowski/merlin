import XCTest
@testable import Merlin

/// Phase 315a — failing tests for the `merlin-discipline scan` report formatter.
final class DisciplineScanReportTests: XCTestCase {

    private func finding(_ category: FindingCategory,
                         _ severity: Severity,
                         summary: String) -> Finding {
        Finding(id: UUID(), category: category, severity: severity,
                summary: summary, detail: "detail for \(summary)",
                suggestedAction: nil, createdAt: Date(), lastSeenAt: Date())
    }

    func testScanReportGroupsFindingsByCategory() {
        let findings = [
            finding(.ungatedTarget, .block, summary: "OrphanTarget"),
            finding(.stubbedImplementation, .nudge, summary: "Foo.swift:10"),
        ]
        let report = DisciplineCLI.formatScanReport(findings)
        XCTAssertTrue(report.contains("ungatedTarget"),
                      "report must name each finding category")
        XCTAssertTrue(report.contains("OrphanTarget"),
                      "report must include each finding's summary")
        XCTAssertTrue(report.contains("stubbedImplementation"))
    }

    func testScanReportHandlesNoFindings() {
        let report = DisciplineCLI.formatScanReport([])
        XCTAssertFalse(report.isEmpty,
                       "an empty scan must still print a summary line")
    }
}
