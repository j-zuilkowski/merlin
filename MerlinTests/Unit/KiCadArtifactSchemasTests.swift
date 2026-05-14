import XCTest
@testable import Merlin

final class KiCadArtifactSchemasTests: XCTestCase {

    func test_allCanonicalSchemas_roundTripJSON() throws {
        let designIntent = DesignIntent(
            designId: "design-ethernet-switch",
            title: "8-Port Ethernet Switch",
            requirements: [Requirement(id: "req-1", text: "Provide 8x RJ45 ports", priority: "must")],
            assumptions: [Assumption(id: "asm-1", text: "Ambient <= 40C", rationale: "Fanless enclosure")],
            components: [ComponentIntent(refdes: "U1", role: "switch-controller", constraints: ["package": "QFN-64"])],
            nets: [NetIntent(name: "ETH_TX_P", role: "differential_pair", source: "U1", destination: "J1")],
            safetyProfile: SafetyProfile(isolationRequired: true, creepageMm: 3.2, notes: ["PoE isolation boundary"]) 
        )

        let extraction = ExtractionReport(
            designId: "design-ethernet-switch",
            sourceType: "vector_pdf",
            extractedComponents: [ExtractedComponent(refdes: "R1", value: "49.9R", footprintHint: "0402")],
            extractedNets: [ExtractedNet(name: "ETH_TX_P", endpoints: ["U1.1", "J1.1"])],
            confidence: ExtractionConfidence(overall: 0.992, criticalFields: 0.997),
            sourceRegions: [SourceRegion(page: 1, x: 10, y: 12, width: 220, height: 144)],
            warnings: ["symbol OCR fallback used"]
        )

        let bom = NormalizedBOM(
            designId: "design-ethernet-switch",
            lines: [BOMLine(lineId: "line-1", mpn: "W5500", quantity: 1, referenceDesignators: ["U1"])],
            vendorMappings: [VendorBOMMapping(vendorId: "digikey", lineId: "line-1", vendorPartNumber: "W5500-ND")],
            substitutions: [SubstitutionCandidate(lineId: "line-1", candidateMPN: "W5100S", reason: "availability")]
        )

        let netClassPlan = NetClassPlan(
            designId: "design-ethernet-switch",
            classes: ["ethernet_diff": ["width_mm": 0.16, "clearance_mm": 0.16]]
        )

        let placementPlan = PlacementPlan(
            designId: "design-ethernet-switch",
            hints: ["U1": "center", "J1": "board_edge"],
            keepouts: ["antenna_zone"]
        )

        let simulation = SimulationScenario(
            scenarioId: "sim-eth-eye",
            designId: "design-ethernet-switch",
            analyses: ["transient", "ac"],
            requiredModelRefs: ["W5500.spice"]
        )

        let fab = FabPackage(
            designId: "design-ethernet-switch",
            gerberArchivePath: "/tmp/gerbers.zip",
            drillFilePath: "/tmp/drill.drl",
            bomPath: "/tmp/bom.csv",
            pickAndPlacePath: "/tmp/pnp.csv",
            vendorOrders: [VendorOrderSummary(vendorId: "digikey", orderReference: "DK-123", paymentAlias: "corp-card-main", totalEstimate: 512.44)]
        )

        let verification = VerificationReport(
            designId: "design-ethernet-switch",
            releaseStatus: "ready_for_release",
            warnings: ["silkscreen label density high"],
            assumptions: ["Production panelization by vendor"],
            approvals: [ApprovalRecord(approver: "hardware-lead", decision: "approved", timestampISO8601: "2026-05-13T18:00:00Z", note: "Looks good")],
            gates: [VerificationGateResult(gate: "drc", passed: true, details: "0 errors")]
        )

        XCTAssertRoundTrips(designIntent)
        XCTAssertRoundTrips(extraction)
        XCTAssertRoundTrips(bom)
        XCTAssertRoundTrips(netClassPlan)
        XCTAssertRoundTrips(placementPlan)
        XCTAssertRoundTrips(simulation)
        XCTAssertRoundTrips(fab)
        XCTAssertRoundTrips(verification)
    }

    func test_snakeCaseKeys_areStable() throws {
        let designIntent = DesignIntent(
            designId: "d1",
            title: "t",
            requirements: [],
            assumptions: [],
            components: [],
            nets: [],
            safetyProfile: SafetyProfile(isolationRequired: false, creepageMm: 0.0, notes: [])
        )
        let data = try JSONEncoder().encode(designIntent)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"design_id\""))
        XCTAssertTrue(json.contains("\"safety_profile\""))
        XCTAssertTrue(json.contains("\"isolation_required\""))
        XCTAssertFalse(json.contains("\"designId\""))
        XCTAssertFalse(json.contains("\"safetyProfile\""))
    }

    func test_artifactStore_rootPath_isUnderDotMerlinElectronics() {
        let store = KiCadArtifactStore(root: "/tmp/project-alpha")
        XCTAssertEqual(store.electronicsRootPath, "/tmp/project-alpha/.merlin/electronics")
    }

    func test_artifactStore_artifactID_isDeterministic() {
        let store = KiCadArtifactStore(root: "/tmp/project-alpha")
        let first = store.artifactID(designId: "design-1", artifactKind: "verification_report")
        let second = store.artifactID(designId: "design-1", artifactKind: "verification_report")
        XCTAssertEqual(first, second)
    }

    func test_verificationReport_supportsWarningsApprovalsAssumptionsAndReleaseStatus() {
        let report = VerificationReport(
            designId: "design-1",
            releaseStatus: "blocked",
            warnings: ["check via annulus"],
            assumptions: ["review pending thermal profile"],
            approvals: [ApprovalRecord(approver: "qa", decision: "rework", timestampISO8601: "2026-05-13T19:00:00Z", note: "needs via spacing fix")],
            gates: [VerificationGateResult(gate: "erc", passed: false, details: "2 errors")]
        )

        XCTAssertEqual(report.releaseStatus, "blocked")
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertEqual(report.assumptions.count, 1)
        XCTAssertEqual(report.approvals.count, 1)
    }

    func test_vendorOrderSummary_storesPaymentAliasOnly() throws {
        let summary = VendorOrderSummary(
            vendorId: "jlcpcb",
            orderReference: "JLC-2026-0001",
            paymentAlias: "corp-ops-card",
            totalEstimate: 129.99
        )

        let data = try JSONEncoder().encode(summary)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"payment_alias\""))
        XCTAssertFalse(json.contains("card_number"))
        XCTAssertFalse(json.contains("payment_details"))
        XCTAssertFalse(json.contains("cvv"))
    }

    private func XCTAssertRoundTrips<T: Codable & Equatable>(_ value: T,
                                                              file: StaticString = #filePath,
                                                              line: UInt = #line) {
        do {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            XCTAssertEqual(decoded, value, file: file, line: line)
        } catch {
            XCTFail("Round-trip failed: \(error)", file: file, line: line)
        }
    }
}
