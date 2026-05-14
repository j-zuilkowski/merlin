import XCTest
@testable import Merlin

final class VendorOrderApprovalTests: XCTestCase {

    func test_vendorCatalog_includesApprovedVendorSet() {
        let names = Set(VendorCatalog.default.vendors.map { $0.canonicalName })

        XCTAssertTrue(names.contains("Digi-Key"))
        XCTAssertTrue(names.contains("Mouser"))
        XCTAssertTrue(names.contains("Arrow"))
        XCTAssertTrue(names.contains("Newark"))
        XCTAssertTrue(names.contains("Farnell"))
        XCTAssertTrue(names.contains("element14"))
        XCTAssertTrue(names.contains("LCSC"))
        XCTAssertTrue(names.contains("Parts Express"))
    }

    func test_everyVendor_hasNativeBOMAdapterContract() {
        let catalog = VendorCatalog.default

        for vendor in catalog.vendors {
            XCTAssertNotNil(catalog.adapter(for: vendor.canonicalName))
        }
    }

    func test_pricingLookup_returnsAdvisoryWithoutApprovingSubstitutions() {
        let policy = VendorOrderPolicy.default
        let result = policy.lookupPricingAndAvailability(
            vendorName: "Digi-Key",
            lineItems: ["ABC-123"]
        )

        XCTAssertEqual(result.mode, .advisory)
        XCTAssertFalse(result.substitutionsApproved)
    }

    func test_orderPrep_doesNotSubmit() {
        let prep = VendorOrderPreparation.prepare(
            vendorName: "Digi-Key",
            normalizedBOMPath: "/tmp/bom.json",
            quantity: 10
        )

        XCTAssertFalse(prep.submitted)
        XCTAssertNotNil(prep.orderPayloadPath)
    }

    func test_orderSubmission_requiresExplicitOrderSubmissionApproval() {
        let prep = VendorOrderPreparation.prepare(
            vendorName: "Mouser",
            normalizedBOMPath: "/tmp/bom.json",
            quantity: 5
        )

        let denied = VendorOrderSubmissionPolicy.default.canSubmit(
            preparation: prep,
            approvalKinds: [.clarification]
        )
        XCTAssertFalse(denied)

        let approved = VendorOrderSubmissionPolicy.default.canSubmit(
            preparation: prep,
            approvalKinds: [.orderSubmission]
        )
        XCTAssertTrue(approved)
    }

    func test_purchaseLimit_blocksOverThresholdOrders() {
        let policy = VendorOrderPolicy.default
        let within = policy.enforcePurchaseLimit(totalUSD: 250.0, limitUSD: 500.0)
        XCTAssertTrue(within.allowed)

        let over = policy.enforcePurchaseLimit(totalUSD: 1200.0, limitUSD: 500.0)
        XCTAssertFalse(over.allowed)
    }

    func test_approvalKinds_includeRequiredElectronicsActions() {
        let all = Set(ElectronicsApprovalKind.allCases.map(\.rawValue))

        XCTAssertTrue(all.contains("clarification"))
        XCTAssertTrue(all.contains("high_stakes_signoff"))
        XCTAssertTrue(all.contains("profile_change"))
        XCTAssertTrue(all.contains("substitution"))
        XCTAssertTrue(all.contains("order_submission"))
        XCTAssertTrue(all.contains("library_generation"))
    }

    func test_orderSummary_storesPaymentAliasOnly() throws {
        let summary = VendorOrderSummary(
            vendorId: "digikey",
            orderReference: "DK-22",
            paymentAlias: "ops-card",
            totalEstimate: 550.00
        )

        let data = try JSONEncoder().encode(summary)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"payment_alias\""))
        XCTAssertFalse(json.contains("card_number"))
        XCTAssertFalse(json.contains("payment_details"))
    }
}
