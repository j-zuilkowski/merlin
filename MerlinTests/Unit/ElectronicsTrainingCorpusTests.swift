import XCTest
@testable import Merlin

final class ElectronicsTrainingCorpusTests: XCTestCase {
    func testLogsAcceptedAndRejectedDesignIntentDrafts() throws {
        let store = ElectronicsTrainingCorpusStore(rootURL: temporaryDirectory("electronics-corpus-intents"))

        try store.recordDesignIntentDraft(
            designId: "sensor-board",
            requirementsText: "battery sensor board",
            draftJSON: #"{"design_id":"sensor-board"}"#,
            decision: .accepted,
            issues: []
        )
        try store.recordDesignIntentDraft(
            designId: "power-supply",
            requirementsText: "isolated supply",
            draftJSON: #"{"design_id":"power-supply"}"#,
            decision: .rejected,
            issues: [ElectronicsSchemaIssue(code: "UNRESOLVED_DECISION", message: "Missing isolation rating")]
        )

        let traces = try store.loadTraces()

        XCTAssertEqual(traces.filter { $0.kind == .designIntentDraft }.count, 2)
        XCTAssertTrue(traces.contains { $0.outcome == .accepted })
        XCTAssertTrue(traces.contains { $0.outcome == .rejected && $0.issues.first?.code == "UNRESOLVED_DECISION" })
    }

    func testLogsCircuitIRValidationFailuresDiagnosticsRepairsAndVerifierOutcomes() throws {
        let store = ElectronicsTrainingCorpusStore(rootURL: temporaryDirectory("electronics-corpus-diagnostics"))

        try store.recordCircuitIRValidation(
            designId: "amp-low-voltage",
            circuitIRJSON: #"{"design_id":"amp-low-voltage"}"#,
            issues: [ElectronicsSchemaIssue(code: "INVALID_NET_ENDPOINT", message: "R1.9 missing")]
        )
        try store.recordDiagnostic(
            designId: "amp-low-voltage",
            diagnosticKind: .erc,
            issues: [ElectronicsSchemaIssue(code: "ERC_UNCONNECTED_PIN", message: "U1.1")]
        )
        try store.recordDiagnostic(
            designId: "amp-low-voltage",
            diagnosticKind: .spice,
            issues: [ElectronicsSchemaIssue(code: "SPICE_MEASURE_FAIL", message: "gain low")]
        )
        try store.recordRepairOutcome(
            designId: "amp-low-voltage",
            diagnosticCode: "ERC_UNCONNECTED_PIN",
            patchJSON: #"{"action":"connect_known_endpoint"}"#,
            verifierStatus: .passed
        )

        let traces = try store.loadTraces()

        XCTAssertTrue(traces.contains { $0.kind == .circuitIRValidation && $0.issues.first?.code == "INVALID_NET_ENDPOINT" })
        XCTAssertTrue(traces.contains { $0.kind == .diagnostic && $0.diagnosticKind == .erc })
        XCTAssertTrue(traces.contains { $0.kind == .diagnostic && $0.diagnosticKind == .spice })
        XCTAssertTrue(traces.contains { $0.kind == .repairOutcome && $0.verifierStatus == .passed })
    }

    func testBuildsVerifierGroundedTrainingPairs() throws {
        let store = ElectronicsTrainingCorpusStore(rootURL: temporaryDirectory("electronics-corpus-pairs"))
        try store.recordDesignIntentDraft(
            designId: "analog-filter",
            requirementsText: "second-order low-pass filter",
            draftJSON: #"{"design_id":"analog-filter"}"#,
            decision: .accepted,
            issues: []
        )
        try store.recordRepairOutcome(
            designId: "analog-filter",
            diagnosticCode: "SPICE_MEASURE_FAIL",
            patchJSON: #"{"parameter":"r_feedback","value":10000}"#,
            verifierStatus: .passed
        )

        let pairs = try store.trainingPairs()

        XCTAssertTrue(pairs.contains { $0.kind == .requirementsToIntent && $0.accepted })
        XCTAssertTrue(pairs.contains { $0.kind == .patchToVerifierResult && $0.accepted })
    }

    func testEvaluationScenarioManifestCoversPlannedFixtures() throws {
        let manifest = try ElectronicsEvaluationManifest.load(
            from: repoRoot().appendingPathComponent("plugins/electronics/evaluation/scenarios.json")
        )
        let ids = Set(manifest.scenarios.map(\.id))

        XCTAssertTrue(ids.contains("sensor_board"))
        XCTAssertTrue(ids.contains("power_supply"))
        XCTAssertTrue(ids.contains("analog_filter"))
        XCTAssertTrue(ids.contains("amp_low_voltage_audio"))
        XCTAssertTrue(ids.contains("amp_mains_power_supply"))
        XCTAssertTrue(manifest.scenarios.allSatisfy { !$0.requiredGates.isEmpty })
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
