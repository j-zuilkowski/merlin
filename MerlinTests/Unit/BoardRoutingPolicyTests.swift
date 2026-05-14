import XCTest
@testable import Merlin

final class BoardRoutingPolicyTests: XCTestCase {

    func test_boardProfileCatalog_hasExpectedOrder() {
        let ids = BoardProfileCatalog.defaultProfiles.map(\.id)
        XCTAssertEqual(ids, ["jlcpcb_2layer_default", "pcbway_2layer", "oshpark_2layer", "custom"])
    }

    func test_ethernetNetClasses_includeDifferentialRulesAnd100OhmTarget() {
        let plan = NetClassPlanner().buildEthernetPlan(designId: "design-eth")

        XCTAssertEqual(plan.designId, "design-eth")
        XCTAssertTrue(plan.classes.keys.contains("ethernet_100base_tx"))
        XCTAssertTrue(plan.classes.keys.contains("ethernet_1000base_t"))
        XCTAssertEqual(plan.classes["ethernet_100base_tx"]?["differential_impedance_ohms"], 100.0)
        XCTAssertEqual(plan.classes["ethernet_1000base_t"]?["differential_impedance_ohms"], 100.0)
    }

    func test_placementOrder_followsDomainPriority() {
        let order = PlacementPlanner().defaultOrdering
        XCTAssertEqual(order, ["mechanical", "safety", "power", "ethernet", "controller", "io", "dft"])
    }

    func test_freeRoutingProfile_usesDSNSESAndHasTimeoutAndIterationFields() {
        let profile = FreeRoutingProfile.default
        XCTAssertEqual(profile.interchange, .dsnSes)
        XCTAssertGreaterThan(profile.timeoutSeconds, 0)
        XCTAssertGreaterThan(profile.maxIterations, 0)
    }

    func test_routeRecoveryPolicy_mayAutoAdjustPlacementAndNetClasses() {
        let policy = RouteRecoveryPolicy.default
        XCTAssertTrue(policy.mayAdjustPlacement)
        XCTAssertTrue(policy.mayAdjustNetClasses)
    }

    func test_routeRecoveryPolicy_requiresApprovalForLayerOrFabricatorChanges() {
        let policy = RouteRecoveryPolicy.default
        XCTAssertTrue(policy.requiresApprovalForLayerCountChange)
        XCTAssertTrue(policy.requiresApprovalForFabricatorProfileChange)
    }

    func test_routeIterationBudget_defaultsAndEarlyStopThreshold() {
        let policy = RouteIterationPolicy.default
        XCTAssertEqual(policy.maxIterations, 15)
        XCTAssertEqual(policy.noImprovementEarlyStopThreshold, 3)
    }
}
