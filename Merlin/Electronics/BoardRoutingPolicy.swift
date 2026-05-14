import Foundation

enum BoardProfileCatalog {
    static let defaultProfiles: [BoardProfile] = [
        .jlcpcb2LayerDefault,
        BoardProfile(
            id: "pcbway_2layer",
            fabricator: "PCBWay",
            layerCount: 2,
            stackup: [
                StackupLayer(name: "F.Cu", kind: "copper"),
                StackupLayer(name: "B.Cu", kind: "copper"),
            ],
            copperWeightOz: 1.0,
            minTraceMm: 0.15,
            minClearanceMm: 0.15,
            minViaDrillMm: 0.30,
            minViaPadMm: 0.60,
            copperToEdgeMm: 0.25,
            impedanceRequirements: [],
            differentialPairRules: [.ethernet100BaseTX, .ethernet1000BaseT]
        ),
        BoardProfile(
            id: "oshpark_2layer",
            fabricator: "OSH Park",
            layerCount: 2,
            stackup: [
                StackupLayer(name: "F.Cu", kind: "copper"),
                StackupLayer(name: "B.Cu", kind: "copper"),
            ],
            copperWeightOz: 1.0,
            minTraceMm: 0.127,
            minClearanceMm: 0.127,
            minViaDrillMm: 0.254,
            minViaPadMm: 0.508,
            copperToEdgeMm: 0.254,
            impedanceRequirements: [],
            differentialPairRules: [.ethernet100BaseTX, .ethernet1000BaseT]
        ),
        BoardProfile(
            id: "custom",
            fabricator: "Custom",
            layerCount: 2,
            stackup: [
                StackupLayer(name: "F.Cu", kind: "copper"),
                StackupLayer(name: "B.Cu", kind: "copper"),
            ],
            copperWeightOz: 1.0,
            minTraceMm: 0.15,
            minClearanceMm: 0.15,
            minViaDrillMm: 0.30,
            minViaPadMm: 0.60,
            copperToEdgeMm: 0.25,
            impedanceRequirements: [],
            differentialPairRules: []
        ),
    ]
}

struct NetClassPlanner: Sendable {
    func buildEthernetPlan(designId: String) -> NetClassPlan {
        NetClassPlan(
            designId: designId,
            classes: [
                "ethernet_100base_tx": [
                    "differential_impedance_ohms": DifferentialPairRule.ethernet100BaseTX.differentialImpedanceOhms,
                    "intra_pair_skew_max_mm": DifferentialPairRule.ethernet100BaseTX.intraPairSkewMaxMm,
                ],
                "ethernet_1000base_t": [
                    "differential_impedance_ohms": DifferentialPairRule.ethernet1000BaseT.differentialImpedanceOhms,
                    "intra_pair_skew_max_mm": DifferentialPairRule.ethernet1000BaseT.intraPairSkewMaxMm,
                    "pair_to_pair_skew_max_mm": DifferentialPairRule.ethernet1000BaseT.pairToPairSkewMaxMm ?? 0,
                ],
            ]
        )
    }
}

struct PlacementPlanner: Sendable {
    let defaultOrdering: [String] = ["mechanical", "safety", "power", "ethernet", "controller", "io", "dft"]
}

struct FreeRoutingProfile: Codable, Sendable, Equatable {
    enum Interchange: String, Codable, Sendable, Equatable {
        case dsnSes = "dsn_ses"
    }

    var interchange: Interchange
    var timeoutSeconds: Int
    var maxIterations: Int

    static let `default` = FreeRoutingProfile(
        interchange: .dsnSes,
        timeoutSeconds: 120,
        maxIterations: 15
    )
}

struct RouteRecoveryPolicy: Codable, Sendable, Equatable {
    var mayAdjustPlacement: Bool
    var mayAdjustNetClasses: Bool
    var requiresApprovalForLayerCountChange: Bool
    var requiresApprovalForFabricatorProfileChange: Bool

    static let `default` = RouteRecoveryPolicy(
        mayAdjustPlacement: true,
        mayAdjustNetClasses: true,
        requiresApprovalForLayerCountChange: true,
        requiresApprovalForFabricatorProfileChange: true
    )
}

struct RouteIterationPolicy: Codable, Sendable, Equatable {
    var maxIterations: Int
    var noImprovementEarlyStopThreshold: Int

    static let `default` = RouteIterationPolicy(
        maxIterations: 15,
        noImprovementEarlyStopThreshold: 3
    )
}
