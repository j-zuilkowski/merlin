import XCTest
@testable import Merlin

final class ElectronicsEvidenceArtifactAdapterTests: XCTestCase {
    func testCleanVerifierArtifactsReachFabReadyWithoutReleaseApproval() throws {
        let root = temporaryDirectory("evidence-adapter-clean")
        let paths = try writeCleanArtifacts(root: root)
        let evidence = try ElectronicsEvidenceArtifactAdapter().buildEvidence(paths)

        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: loadFixture("amp_low_voltage_audio/design_intent.json"),
            circuitIR: loadFixture("amp_low_voltage_audio/circuit_ir.json"),
            outputDirectory: root.appendingPathComponent("out", isDirectory: true),
            evidence: evidence
        ))

        XCTAssertEqual(result.status, .fabReady)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.pcbStatus, .pcbVerified)
        XCTAssertEqual(result.spiceStatus, .passed)
        XCTAssertEqual(result.fabricationStatus, .fabReady)
    }

    func testBlockingDRCViolationBlocksPCBAndHarness() throws {
        let root = temporaryDirectory("evidence-adapter-drc")
        var paths = try writeCleanArtifacts(root: root)
        paths.drcReportPath = try write(
            "drc.json",
            in: root,
            contents: """
            {
              "violations": [
                {
                  "id": "drc-1",
                  "code": "clearance",
                  "severity": "error",
                  "message": "Track clearance is below rule.",
                  "refs": ["R1", "C1"]
                }
              ]
            }
            """
        ).path

        let evidence = try ElectronicsEvidenceArtifactAdapter().buildEvidence(paths)
        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: loadFixture("amp_low_voltage_audio/design_intent.json"),
            circuitIR: loadFixture("amp_low_voltage_audio/circuit_ir.json"),
            outputDirectory: root.appendingPathComponent("out", isDirectory: true),
            evidence: evidence
        ))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.pcbStatus, .blocked)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "BLOCKING_DRC_VIOLATION" })
        XCTAssertTrue(result.missingEvidence.contains("PCB_VERIFIED"))
    }

    func testInvalidBOMVendorEvidenceBlocksFabrication() throws {
        let root = temporaryDirectory("evidence-adapter-bom")
        var paths = try writeCleanArtifacts(root: root)
        paths.vendorAvailabilityPath = try write(
            "availability.json",
            in: root,
            contents: """
            [
              {
                "line_id": "line-1",
                "mpn": "RC0603FR-0710KL",
                "vendor_id": "digikey",
                "vendor_part_number": "",
                "lifecycle": "active",
                "in_stock_quantity": 10
              }
            ]
            """
        ).path

        let evidence = try ElectronicsEvidenceArtifactAdapter().buildEvidence(paths)
        let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
            designIntent: loadFixture("amp_low_voltage_audio/design_intent.json"),
            circuitIR: loadFixture("amp_low_voltage_audio/circuit_ir.json"),
            outputDirectory: root.appendingPathComponent("out", isDirectory: true),
            evidence: evidence
        ))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertNotEqual(result.fabricationStatus, .fabReady)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "BOM_VENDOR_PART_NUMBER_REQUIRED" })
    }

    private func writeCleanArtifacts(root: URL) throws -> ElectronicsEvidenceArtifactPaths {
        let erc = try write("erc.json", in: root, contents: #"{"violations":[]}"#)
        let drc = try write("drc.json", in: root, contents: #"{"violations":[]}"#)
        let scenario = try write(
            "scenario.json",
            in: root,
            contents: """
            {
              "scenario_id": "amp-low-voltage-output-stage",
              "design_id": "amp_low_voltage_audio",
              "circuit_path": "\(root.appendingPathComponent("output-stage.cir").path)",
              "analyses": ["tran", "ac"],
              "required_model_refs": ["MJ15003G"],
              "measurement_envelopes": [
                { "name": "output_power_w", "min": 24.0, "max": 28.0 },
                { "name": "thd_percent", "max": 1.0 }
              ]
            }
            """
        )
        _ = try write(
            "output-stage.cir",
            in: root,
            contents: """
            * amp output stage
            V1 in 0 SIN(0 1 1000)
            RLOAD out 0 8
            .tran 10u 10m
            .ac dec 10 20 20k
            .meas tran output_power_w PARAM='25.1'
            .meas tran thd_percent PARAM='0.72'
            .end
            """
        )
        let models = try write(
            "models.json",
            in: root,
            contents: #"[{"model_ref":"MJ15003G","legally_usable":true,"is_generic":false}]"#
        )
        let spice = try write(
            "ngspice.log",
            in: root,
            contents: """
            output_power_w = 25.1
            thd_percent = 0.72
            """
        )
        let bom = try write(
            "bom.json",
            in: root,
            contents: """
            {
              "design_id": "amp_low_voltage_audio",
              "lines": [
                {
                  "line_id": "line-1",
                  "mpn": "RC0603FR-0710KL",
                  "quantity": 2,
                  "reference_designators": ["R1", "R2"]
                }
              ],
              "vendor_mappings": [
                {
                  "vendor_id": "digikey",
                  "line_id": "line-1",
                  "vendor_part_number": "311-10.0KHRCT-ND"
                }
              ],
              "substitutions": []
            }
            """
        )
        let availability = try write(
            "availability.json",
            in: root,
            contents: """
            [
              {
                "line_id": "line-1",
                "mpn": "RC0603FR-0710KL",
                "vendor_id": "digikey",
                "vendor_part_number": "311-10.0KHRCT-ND",
                "lifecycle": "active",
                "in_stock_quantity": 100
              }
            ]
            """
        )
        let gerbers = try write("gerbers.zip", in: root, contents: "PK\u{03}\u{04}")
        let drill = try write("amp.drl", in: root, contents: "M48\n")
        let pnp = try write("pnp.csv", in: root, contents: "Designator,Mid X,Mid Y,Layer,Rotation\n")
        let fabReport = try write("fab-report.json", in: root, contents: #"{"status":"ok"}"#)
        let verification = try write("verification.json", in: root, contents: #"{"status":"FAB_READY"}"#)
        let fabrication = try write(
            "fabrication.json",
            in: root,
            contents: """
            {
              "profile_id": "jlcpcb_2_layer",
              "outputs": [
                { "kind": "gerber_archive", "path": "\(gerbers.path)" },
                { "kind": "excellon_drill", "path": "\(drill.path)" },
                { "kind": "normalized_bom", "path": "\(bom.path)" },
                { "kind": "pick_and_place", "path": "\(pnp.path)" },
                { "kind": "fabrication_report", "path": "\(fabReport.path)" }
              ],
              "cam_report_path": "\(fabReport.path)"
            }
            """
        )

        return ElectronicsEvidenceArtifactPaths(
            ercReportPaths: [erc.path],
            drcReportPath: drc.path,
            spiceScenarioPath: scenario.path,
            spiceModelRecordsPath: models.path,
            ngspiceOutputPath: spice.path,
            normalizedBOMPath: bom.path,
            vendorAvailabilityPath: availability.path,
            fabricationEvidencePath: fabrication.path,
            verificationReportPath: verification.path,
            releasePackagePath: nil,
            approvals: [],
            evidenceApprovals: [.highStakesSignoff]
        )
    }

    private func loadFixture<T: Decodable>(_ relativePath: String) throws -> T {
        let url = repoRoot()
            .appendingPathComponent("plugins/electronics/fixtures")
            .appendingPathComponent(relativePath)
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func write(_ name: String, in root: URL, contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
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
