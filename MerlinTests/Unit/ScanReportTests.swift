import XCTest
@testable import Merlin

final class ScanReportTests: XCTestCase {

    func testScanReportIsSendable() {
        func requiresSendable<T: Sendable>(_ value: T) {}
        let report = ScanReport(findings: [], durationMs: 42, scannedAt: Date())
        requiresSendable(report)
    }

    func testScanReportFields() {
        let now = Date()
        let f = Finding(
            id: UUID(), category: .phaseDrift, severity: .nudge,
            summary: "s", detail: "d", suggestedAction: nil,
            createdAt: now, lastSeenAt: now
        )
        let report = ScanReport(findings: [f], durationMs: 100, scannedAt: now)
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.durationMs, 100)
        XCTAssertEqual(report.scannedAt, now)
    }
}
