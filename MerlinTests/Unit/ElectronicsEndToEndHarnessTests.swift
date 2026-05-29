import XCTest
@testable import Merlin

final class ElectronicsEndToEndHarnessTests: XCTestCase {
    func testIntentOnlyCannotCompleteWithoutCircuitIRAndVerifierEvidence() throws {
        let intent: DesignIntent = try loadFixture("amp_low_voltage_audio/design_intent.json")

        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: intent,
            circuitIR: nil,
            outputDirectory: temporaryDirectory("intent-only"),
            evidence: .none
        ))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.missingEvidence.contains("circuit_ir"))
        XCTAssertTrue(result.missingEvidence.contains("SCHEMATIC_VERIFIED"))
        XCTAssertNotEqual(result.status.rawValue, "COMPLETE")
    }

    func testAmpLowVoltageFixtureReachesFabReadyNotCompleteWithoutReleaseApproval() throws {
        let intent: DesignIntent = try loadFixture("amp_low_voltage_audio/design_intent.json")
        let circuitIR: CircuitIR = try loadFixture("amp_low_voltage_audio/circuit_ir.json")

        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: intent,
            circuitIR: circuitIR,
            outputDirectory: temporaryDirectory("amp-fab-ready"),
            evidence: .ampLowVoltageVerified
        ))

        XCTAssertEqual(result.schematicStatus, .schematicVerified)
        XCTAssertEqual(result.pcbStatus, .pcbVerified)
        XCTAssertEqual(result.spiceStatus, .passed)
        XCTAssertEqual(result.fabricationStatus, .fabReady)
        XCTAssertEqual(result.status, .fabReady)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.missingEvidence.contains("release_package"))
        XCTAssertTrue(result.missingEvidence.contains("release_approval"))
    }

    func testAmpLowVoltageFixtureRequiresSPICEEvidenceBeforeFabReadyOrComplete() throws {
        let intent: DesignIntent = try loadFixture("amp_low_voltage_audio/design_intent.json")
        let circuitIR: CircuitIR = try loadFixture("amp_low_voltage_audio/circuit_ir.json")
        var evidence = ElectronicsEndToEndEvidence.ampLowVoltageVerified
        evidence.spice = nil

        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: intent,
            circuitIR: circuitIR,
            outputDirectory: temporaryDirectory("amp-missing-spice"),
            evidence: evidence
        ))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.missingEvidence.contains("spice_measurements"))
        XCTAssertNotEqual(result.fabricationStatus, .fabReady)
        XCTAssertNotEqual(result.status, .complete)
    }

    func testCompleteRequiresReleasePackageAndApproval() throws {
        let intent: DesignIntent = try loadFixture("amp_low_voltage_audio/design_intent.json")
        let circuitIR: CircuitIR = try loadFixture("amp_low_voltage_audio/circuit_ir.json")
        var evidence = ElectronicsEndToEndEvidence.ampLowVoltageVerified
        evidence.fabrication.releasePackagePath = "/tmp/amp-low-voltage/release.zip"
        evidence.fabrication.approvals.append(ElectronicsApprovalRecord(
            kind: .release,
            approvedBy: "test",
            summary: "Release package approved"
        ))

        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: intent,
            circuitIR: circuitIR,
            outputDirectory: temporaryDirectory("amp-complete"),
            evidence: evidence
        ))

        XCTAssertEqual(result.status, .complete)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.missingEvidence.isEmpty)
    }

    func testMainsPowerBoardBlocksWithoutHighStakesSignoffAndNeverCertifiesSafety() throws {
        let intent: DesignIntent = try loadFixture("amp_mains_power_supply/design_intent.json")
        let circuitIR: CircuitIR = try loadFixture("amp_mains_power_supply/circuit_ir.json")

        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: intent,
            circuitIR: circuitIR,
            outputDirectory: temporaryDirectory("mains-without-signoff"),
            evidence: .mainsPowerCADVerified,
            approvals: []
        ))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertFalse(result.isComplete)
        XCTAssertFalse(result.certifiesSafety)
        XCTAssertTrue(result.missingEvidence.contains("high_stakes_signoff"))
        XCTAssertTrue(result.diagnostics.contains { $0.code == "HIGH_STAKES_REVIEW_REQUIRED" })
    }

    private func loadFixture<T: Decodable>(_ relativePath: String) throws -> T {
        let url = repoRoot()
            .appendingPathComponent("plugins/electronics/fixtures")
            .appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func temporaryDirectory(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MerlinTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
