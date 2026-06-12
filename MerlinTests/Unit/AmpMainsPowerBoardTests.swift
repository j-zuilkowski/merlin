import XCTest
@testable import Merlin

final class AmpMainsPowerBoardTests: XCTestCase {
    func testMainsPowerDesignIntentFixtureCapturesSeparateHighStakesBoard() throws {
        let intent: DesignIntent = try loadFixture("design_intent.json")
        let text = ([intent.title] + intent.requirements.map(\.text) + intent.assumptions.map(\.text) + intent.safetyProfile.notes).joined(separator: " ").lowercased()

        XCTAssertEqual(intent.designId, "amp_mains_power_supply")
        XCTAssertEqual(intent.approval.status, .draft)
        XCTAssertTrue(intent.boards.contains { $0.id == "amp_mains_power_supply" && $0.safetyDomain == "hazardous_mains_primary" })
        XCTAssertTrue(intent.safetyProfile.isolationRequired)
        XCTAssertGreaterThanOrEqual(intent.safetyProfile.creepageMm, 6.4)

        for required in ["mains inlet", "fuse", "switch", "protective earth", "transformer primary", "secondary interface", "creepage", "qualified safety review"] {
            XCTAssertTrue(text.contains(required), "Missing mains board requirement text: \(required)")
        }
        XCTAssertTrue(intent.unresolvedDecisions.contains { $0.blocking })
    }

    func testMainsPowerCircuitIRRepresentsRequiredSafetyBlocksAndConstraints() throws {
        let circuitIR: CircuitIR = try loadFixture("circuit_ir.json")
        let roles = circuitIR.components.map(\.role).joined(separator: " ").lowercased()
        let constraints = circuitIR.constraints.map { "\($0.kind) \($0.target) \($0.value)" }.joined(separator: " ").lowercased()

        XCTAssertEqual(circuitIR.boardId, "amp_mains_power_supply")
        for required in ["mains inlet", "fuse", "mains switch", "protective earth bond", "transformer primary", "isolated secondary interface"] {
            XCTAssertTrue(roles.contains(required), "Missing required power-board role: \(required)")
        }
        XCTAssertTrue(constraints.contains("creepage"))
        XCTAssertTrue(constraints.contains("clearance"))
        XCTAssertTrue(constraints.contains("qualified safety review"))
        XCTAssertTrue(circuitIR.nets.allSatisfy { !$0.safetyDomain.isEmpty })
    }

    func testHighStakesSafetyPolicyRequiresReviewAndBlocksCertificationClaims() throws {
        let intent: DesignIntent = try loadFixture("design_intent.json")
        let evaluation = HighStakesSafetyPolicy().evaluate(intent: intent, grantedApprovals: [])

        XCTAssertEqual(evaluation.status, .blocked)
        XCTAssertTrue(evaluation.requiredApprovals.contains(.highStakesSignoff))
        XCTAssertFalse(evaluation.certifiesSafety)
        XCTAssertTrue(evaluation.issues.contains { $0.code == "HIGH_STAKES_REVIEW_REQUIRED" })

        let claim = HighStakesSafetyPolicy().evaluateCertificationClaim("This mains board is safe to build and use.")

        XCTAssertFalse(claim.allowed)
        XCTAssertEqual(claim.issue.code, "SAFETY_CERTIFICATION_CLAIM_BLOCKED")
    }

    func testCADVerificationDoesNotCertifyBuildOrUseSafety() throws {
        let intent: DesignIntent = try loadFixture("design_intent.json")
        let cadVerified = HighStakesSafetyPolicy().evaluateCADVerification(
            intent: intent,
            schematicVerified: true,
            pcbVerified: true,
            fabReady: true,
            grantedApprovals: [.highStakesSignoff]
        )

        XCTAssertTrue(cadVerified.cadArtifactsMayBePrepared)
        XCTAssertFalse(cadVerified.certifiesSafety)
        XCTAssertTrue(cadVerified.disclaimers.contains { $0.lowercased().contains("does not certify") })
    }

    func testIrreversiblePowerBoardActionsRequireSpecificApprovals() {
        let policy = IrreversibleElectronicsActionPolicy()

        XCTAssertFalse(policy.canSubmit(.fabricationOrder, approvals: [.highStakesSignoff]).approved)
        XCTAssertFalse(policy.canSubmit(.vendorOrder, approvals: [.highStakesSignoff]).approved)
        XCTAssertTrue(policy.canSubmit(.fabricationOrder, approvals: [.highStakesSignoff, .fabricationSubmission]).approved)
        XCTAssertTrue(policy.canSubmit(.vendorOrder, approvals: [.highStakesSignoff, .orderSubmission]).approved)
    }

    private func loadFixture<T: Decodable>(_ name: String) throws -> T {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("plugins/electronics/fixtures/amp_mains_power_supply")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
