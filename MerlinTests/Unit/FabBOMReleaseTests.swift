import XCTest
@testable import Merlin

final class FabBOMReleaseTests: XCTestCase {
    func testNormalizedBOMRequiresMPNQuantityReferenceAndVendorMapping() {
        let bom = NormalizedBOM(
            designId: "amp-low-voltage",
            lines: [
                BOMLine(lineId: "line-1", mpn: "MJ15003G", quantity: 1, referenceDesignators: ["QOUT1"]),
                BOMLine(lineId: "line-2", mpn: "", quantity: 0, referenceDesignators: []),
            ],
            vendorMappings: [
                VendorBOMMapping(vendorId: "digikey", lineId: "line-1", vendorPartNumber: "MJ15003GOS-ND"),
            ],
            substitutions: []
        )

        let result = NormalizedBOMValidator().validate(bom)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.code == "BOM_MPN_REQUIRED" })
        XCTAssertTrue(result.issues.contains { $0.code == "BOM_QUANTITY_REQUIRED" })
        XCTAssertTrue(result.issues.contains { $0.code == "BOM_REFDES_REQUIRED" })
        XCTAssertTrue(result.issues.contains { $0.code == "BOM_VENDOR_MAPPING_REQUIRED" })
    }

    func testVendorAvailabilityDiagnosticsBlockMissingMPNAndUnavailableParts() {
        let diagnostics = VendorAvailabilityChecker().evaluate(
            bom: validBOM,
            availability: [
                VendorAvailability(lineId: "line-1", mpn: "MJ15003G", vendorId: "digikey", vendorPartNumber: "MJ15003GOS-ND", lifecycle: .active, inStockQuantity: 0),
            ]
        )

        XCTAssertFalse(diagnostics.isOrderable)
        XCTAssertTrue(diagnostics.issues.contains { $0.code == "BOM_VENDOR_AVAILABILITY_MISSING" })
        XCTAssertTrue(diagnostics.issues.contains { $0.code == "BOM_VENDOR_OUT_OF_STOCK" })
    }

    func testFabricationEvidenceRequiresGerberDrillPlacementAndReport() {
        let evidence = FabricationOutputEvidence(
            profileId: "jlcpcb_2_layer",
            outputs: [
                FabricationOutput(kind: .gerberArchive, path: "/tmp/amp/gerbers.zip"),
                FabricationOutput(kind: .normalizedBOM, path: "/tmp/amp/bom.csv"),
            ],
            camReportPath: nil
        )

        let result = FabricationEvidenceValidator().validate(evidence, profile: .jlcPCBTwoLayer)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.missingKinds.contains(.excellonDrill))
        XCTAssertTrue(result.missingKinds.contains(.pickAndPlace))
        XCTAssertTrue(result.missingKinds.contains(.fabricationReport))
    }

    func testFabricatorProfileValidationBlocksUnsupportedStackupAndRules() {
        var boardProfile = BoardProfile.jlcpcb2LayerDefault
        boardProfile.layerCount = 4
        boardProfile.minTraceMm = 0.09
        boardProfile.minClearanceMm = 0.09
        let candidate = PCBBoardCandidate(
            boardProfile: boardProfile,
            outline: BoardOutline(widthMm: 90, heightMm: 70),
            footprintAssignments: [],
            netClassPlan: NetClassPlan(designId: "amp-low-voltage", classes: [:]),
            placementPlan: PlacementPlan(designId: "amp-low-voltage", hints: [:], keepouts: [])
        )

        let result = FabricatorProfileValidator().validate(candidate, profile: .jlcPCBTwoLayer)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.code == "FAB_PROFILE_LAYER_COUNT_UNSUPPORTED" })
        XCTAssertTrue(result.issues.contains { $0.code == "FAB_PROFILE_TRACE_UNSUPPORTED" })
        XCTAssertTrue(result.issues.contains { $0.code == "FAB_PROFILE_CLEARANCE_UNSUPPORTED" })
    }

    func testIrreversibleFabricationAndOrderSubmissionRequireExplicitApprovals() {
        let policy = IrreversibleElectronicsActionPolicy()

        XCTAssertFalse(policy.canSubmit(.fabricationOrder, approvals: [.release]).approved)
        XCTAssertFalse(policy.canSubmit(.vendorOrder, approvals: [.fabricationSubmission]).approved)
        XCTAssertTrue(policy.canSubmit(.fabricationOrder, approvals: [.fabricationSubmission]).approved)
        XCTAssertTrue(policy.canSubmit(.vendorOrder, approvals: [.orderSubmission]).approved)
    }

    func testFabReadyAndCompleteRequireSeparateEvidence() {
        let fabReady = FabricationReleaseGate().evaluate(.fabReadyFixture)

        XCTAssertEqual(fabReady.status, .fabReady)
        XCTAssertTrue(fabReady.canPackageRelease)
        XCTAssertFalse(fabReady.isComplete)

        var completeEvidence = FabricationReleaseEvidence.fabReadyFixture
        completeEvidence.releasePackagePath = "/tmp/amp/release.zip"
        completeEvidence.approvals.append(ElectronicsApprovalRecord(kind: .release, approvedBy: "user", summary: "Release package approved"))

        let complete = FabricationReleaseGate().evaluate(completeEvidence)

        XCTAssertEqual(complete.status, .complete)
        XCTAssertTrue(complete.isComplete)
    }

    func testFabReadyRequiresArtifactBackedBOMVendorDatasheetAndOrderEvidence() {
        var evidence = FabricationReleaseEvidence.fabReadyFixture
        evidence.normalizedBOMPath = nil
        evidence.vendorAvailabilityPath = nil
        evidence.datasheetEvidencePath = nil
        evidence.vendorOrderPackagePath = nil

        let result = FabricationReleaseGate().evaluate(evidence)

        XCTAssertEqual(result.status, .blocked)
        XCTAssertFalse(result.canPackageRelease)
        XCTAssertTrue(result.missingEvidence.contains("normalized_bom"))
        XCTAssertTrue(result.missingEvidence.contains("vendor_availability"))
        XCTAssertTrue(result.missingEvidence.contains("datasheet_evidence"))
        XCTAssertTrue(result.missingEvidence.contains("vendor_order_package"))
    }

    private var validBOM: NormalizedBOM {
        NormalizedBOM(
            designId: "amp-low-voltage",
            lines: [
                BOMLine(lineId: "line-1", mpn: "MJ15003G", quantity: 1, referenceDesignators: ["QOUT1"]),
                BOMLine(lineId: "line-2", mpn: "1N5408", quantity: 4, referenceDesignators: ["D1", "D2", "D3", "D4"]),
            ],
            vendorMappings: [
                VendorBOMMapping(vendorId: "digikey", lineId: "line-1", vendorPartNumber: "MJ15003GOS-ND"),
            ],
            substitutions: []
        )
    }
}
