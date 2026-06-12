import XCTest
@testable import Merlin

final class SchematicVerifiedStatusTests: XCTestCase {
    func testSchematicVerifiedRequiresAllEvidence() {
        let result = SchematicVerificationGate().evaluate(.missingEvidence)

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.missingEvidence.contains(.approvedDesignIntent))
        XCTAssertTrue(result.missingEvidence.contains(.circuitIRValidation))
        XCTAssertTrue(result.missingEvidence.contains(.kicadProject))
        XCTAssertTrue(result.missingEvidence.contains(.kicadSchematic))
        XCTAssertTrue(result.missingEvidence.contains(.ercReport))
        XCTAssertTrue(result.missingEvidence.contains(.schematicVerificationReport))
    }

    func testSchematicVerifiedBlocksOnERCViolations() {
        var evidence = SchematicVerificationEvidence.complete
        evidence.blockingERCViolations = [
            KiCadERCViolation(id: "erc-1", code: "pin_conflict", severity: .error, message: "Output conflict", refs: ["U1.1"]),
        ]

        let result = SchematicVerificationGate().evaluate(evidence)

        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.diagnostics.map(\.code), ["BLOCKING_ERC_VIOLATION"])
    }

    func testSchematicVerifiedBlocksOnVerificationBlockingERCWarnings() {
        var evidence = SchematicVerificationEvidence.complete
        evidence.blockingERCViolations = [
            KiCadERCViolation(
                id: "erc-warning-1",
                code: "multiple_net_names",
                severity: .warning,
                message: "Two labels are attached to the same schematic item.",
                refs: ["PRE_OUT", "TONE_OUT"]
            ),
        ]

        let result = SchematicVerificationGate().evaluate(evidence)

        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.diagnostics.map(\.code), ["BLOCKING_ERC_VIOLATION"])
    }

    func testSchematicVerifiedStatusRequiresVerifiedRepairLoopResult() {
        var evidence = SchematicVerificationEvidence.complete
        evidence.repairLoopStatus = .blocked

        let result = SchematicVerificationGate().evaluate(evidence)

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "SCHEMATIC_REPAIR_NOT_VERIFIED" })
    }

    func testSchematicVerifiedPassesWithCompleteEvidenceAndNoBlockingERC() {
        let result = SchematicVerificationGate().evaluate(.complete)

        XCTAssertEqual(result.status, .schematicVerified)
        XCTAssertEqual(result.report.status, .schematicVerified)
        XCTAssertEqual(result.report.statusCode, "SCHEMATIC_VERIFIED")
    }
}
