import XCTest
@testable import Merlin

final class DriftSeverityTests: XCTestCase {

    func testAllCasesExist() {
        let cases: [DriftSeverity] = [.green, .yellow, .red, .orange]
        XCTAssertEqual(cases.count, 4)
    }

    func testDriftFindingIdentifiable() {
        let f = DriftFinding(
            id: UUID(),
            phaseID: "233b",
            surface: "ProviderBudget",
            severity: .red,
            evidence: "No match in source tree",
            suggestedAction: "Restore or write addendum"
        )
        XCTAssertNotNil(f.id)
    }

    func testDriftFindingIsSendable() {
        func requiresSendable<T: Sendable>(_ value: T) {}
        let f = DriftFinding(
            id: UUID(),
            phaseID: nil,
            surface: "AgenticEngine",
            severity: .green,
            evidence: "Found at AgenticEngine.swift:12",
            suggestedAction: "No action needed"
        )
        requiresSendable(f)
    }
}
