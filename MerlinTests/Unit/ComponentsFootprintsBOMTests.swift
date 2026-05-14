import XCTest
@testable import Merlin

final class ComponentsFootprintsBOMTests: XCTestCase {

    func test_footprintPriority_followsDefinedOrder() {
        let policy = FootprintAssignmentPolicy()

        let existing = policy.assign(
            refdes: "U1",
            existingKiCadFootprint: "QFN-64",
            exactMPNFootprint: "QFN-56",
            packageConstraintFootprint: "QFN",
            projectDefaultFootprint: "GENERIC",
            userClarifiedFootprint: "CUSTOM"
        )
        XCTAssertEqual(existing.source, .existingKiCadField)
        XCTAssertEqual(existing.footprint, "QFN-64")

        let exact = policy.assign(refdes: "U2", existingKiCadFootprint: nil, exactMPNFootprint: "SOT-23", packageConstraintFootprint: "SOT", projectDefaultFootprint: "GENERIC", userClarifiedFootprint: nil)
        XCTAssertEqual(exact.source, .exactMPN)

        let package = policy.assign(refdes: "U3", existingKiCadFootprint: nil, exactMPNFootprint: nil, packageConstraintFootprint: "0603", projectDefaultFootprint: "GENERIC", userClarifiedFootprint: nil)
        XCTAssertEqual(package.source, .packageConstraint)

        let fallback = policy.assign(refdes: "U4", existingKiCadFootprint: nil, exactMPNFootprint: nil, packageConstraintFootprint: nil, projectDefaultFootprint: "GENERIC", userClarifiedFootprint: nil)
        XCTAssertEqual(fallback.source, .projectDefault)

        let clarified = policy.assign(refdes: "U5", existingKiCadFootprint: nil, exactMPNFootprint: nil, packageConstraintFootprint: nil, projectDefaultFootprint: nil, userClarifiedFootprint: "USER-PICKED")
        XCTAssertEqual(clarified.source, .userClarification)
    }

    func test_unknownFootprints_blocksPCBSynthesis() {
        let report = FootprintAssignmentReport(
            assignments: [],
            unknownFootprints: 2
        )

        XCTAssertEqual(report.status, .blockedInputQuality)
        XCTAssertFalse(report.mayProceedToPCBSynthesis)
    }

    func test_generatedLibraryVerification_requiresPinAndPackageChecks() {
        let policy = LibraryVerificationPolicy()
        let report = policy.verify(
            generatedSymbolPinNames: ["VIN", "GND", "EN"],
            generatedFootprintPads: ["1", "2"],
            expectedPinNames: ["VIN", "GND", "EN"],
            expectedPadNumbers: ["1", "2", "3"],
            packageDimensionsMatch: false
        )

        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.requiredChecks.contains("pin_count"))
        XCTAssertTrue(report.requiredChecks.contains("pin_name"))
        XCTAssertTrue(report.requiredChecks.contains("pad_number"))
        XCTAssertTrue(report.requiredChecks.contains("package_dimension"))
    }

    func test_kicadFields_mapToNormalizedBOM() {
        let builder = NormalizedBOMBuilder()
        let bom = builder.build(
            designId: "design-bom",
            kicadRows: [
                [
                    "RefDes": "R1,R2",
                    "value": "10k",
                    "footprint": "Resistor_SMD:R_0603",
                    "manufacturer": "Yageo",
                    "MPN": "RC0603FR-0710KL",
                    "vendor_skus": "Digi-Key:311-10.0KHRCT-ND;Mouser:603-RC0603FR0710KL",
                    "quantity": "2",
                    "DNP": "false",
                    "lifecycle": "active",
                    "substitutions": "RC0603JR-0710KL"
                ]
            ]
        )

        let line = try? XCTUnwrap(bom.lines.first)
        XCTAssertEqual(line??.referenceDesignators, ["R1", "R2"])
        XCTAssertEqual(line??.value, "10k")
        XCTAssertEqual(line??.footprint, "Resistor_SMD:R_0603")
        XCTAssertEqual(line??.manufacturer, "Yageo")
        XCTAssertEqual(line??.mpn, "RC0603FR-0710KL")
        XCTAssertEqual(line??.vendorSKUs["Digi-Key"], "311-10.0KHRCT-ND")
        XCTAssertEqual(line??.quantity, 2)
        XCTAssertEqual(line??.dnp, false)
        XCTAssertEqual(line??.lifecycle, "active")
        XCTAssertEqual(line??.substitutions, ["RC0603JR-0710KL"])
    }

    func test_substitutions_neverSilentlyChangeCriticalFields() {
        let policy = SubstitutionPolicy()
        let decision = policy.evaluate(
            original: BOMLine(
                lineId: "1",
                mpn: "ABC-1",
                quantity: 1,
                referenceDesignators: ["U1"],
                footprint: "QFN-64",
                lifecycle: "active"
            ),
            candidate: BOMLine(
                lineId: "1",
                mpn: "ABC-2",
                quantity: 1,
                referenceDesignators: ["U1"],
                footprint: "BGA-81",
                lifecycle: "obsolete"
            )
        )

        XCTAssertTrue(decision.requiresApproval)
        XCTAssertTrue(decision.reasons.contains("package_changed"))
        XCTAssertTrue(decision.reasons.contains("lifecycle_changed"))
    }

    func test_vendorSourcePolicy_includesApprovedVendors() {
        let policy = VendorSourcePolicy.default
        let vendors = Set(policy.supportedVendors.map { $0.canonicalName })

        XCTAssertTrue(vendors.contains("Digi-Key"))
        XCTAssertTrue(vendors.contains("Mouser"))
        XCTAssertTrue(vendors.contains("Arrow"))
        XCTAssertTrue(vendors.contains("Newark"))
        XCTAssertTrue(vendors.contains("Farnell"))
        XCTAssertTrue(vendors.contains("element14"))
        XCTAssertTrue(vendors.contains("LCSC"))
        XCTAssertTrue(vendors.contains("Parts Express"))
    }
}
