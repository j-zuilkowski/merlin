import Foundation

struct PluginRoleDefinition: Codable, Equatable, Hashable, Sendable {
    var id: String
    var displayName: String
    var pluginID: String
    var scope: String
    var fallbackSlot: AgentSlot
    var requiredCapabilities: [String]
    var recommendedModels: [String]
    var isRequired: Bool

    init(
        id: String,
        displayName: String,
        pluginID: String,
        scope: String,
        fallbackSlot: AgentSlot,
        requiredCapabilities: [String] = [],
        recommendedModels: [String] = [],
        isRequired: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.pluginID = pluginID
        self.scope = scope
        self.fallbackSlot = fallbackSlot
        self.requiredCapabilities = requiredCapabilities
        self.recommendedModels = recommendedModels
        self.isRequired = isRequired
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case pluginID = "pluginId"
        case scope
        case fallbackSlot = "defaultFallback"
        case requiredCapabilities
        case recommendedModels
        case isRequired
    }
}

enum DynamicRoleResolution: Equatable, Sendable {
    case slot(AgentSlot)
    case providerID(String)
    case blocked(code: String)
}

struct DynamicRoleRegistry: Equatable, Sendable {
    private var definitionsByID: [String: PluginRoleDefinition]

    init() {
        definitionsByID = Dictionary(
            uniqueKeysWithValues: Self.builtInRoles.map { ($0.id, $0) }
        )
    }

    var availableRoleIDs: [String] {
        definitionsByID.values
            .sorted { lhs, rhs in
                let lhsRank = Self.sortRank(for: lhs.id)
                let rhsRank = Self.sortRank(for: rhs.id)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.id < rhs.id
            }
            .map(\.id)
    }

    func definition(for roleID: String) -> PluginRoleDefinition? {
        definitionsByID[roleID]
    }

    mutating func register(metadata: RuntimePluginMetadata) {
        register(pluginRoles: metadata.roles, pluginID: metadata.id)
    }

    mutating func register(pluginRoles: [PluginRoleDefinition], pluginID: String) {
        unregisterPluginRoles(pluginID: pluginID)
        for role in pluginRoles where role.pluginID == pluginID {
            definitionsByID[role.id] = role
        }
    }

    mutating func unregisterPluginRoles(pluginID: String) {
        definitionsByID = definitionsByID.filter { _, role in
            role.pluginID != pluginID || role.pluginID == "merlin"
        }
    }

    func resolve(
        roleID: String,
        assignments: [String: String],
        requireAssignment: Bool = false
    ) -> DynamicRoleResolution {
        guard let definition = definitionsByID[roleID] else {
            return .blocked(code: "ROLE_UNAVAILABLE")
        }
        if let providerID = assignments[roleID], !providerID.isEmpty {
            return .providerID(providerID)
        }
        if requireAssignment || definition.isRequired {
            return .blocked(code: "ROLE_UNASSIGNED")
        }
        return .slot(definition.fallbackSlot)
    }

    private static let builtInRoles: [PluginRoleDefinition] = [
        PluginRoleDefinition(
            id: AgentSlot.execute.rawValue,
            displayName: "Execute",
            pluginID: "merlin",
            scope: "core",
            fallbackSlot: .execute
        ),
        PluginRoleDefinition(
            id: AgentSlot.reason.rawValue,
            displayName: "Reason",
            pluginID: "merlin",
            scope: "core",
            fallbackSlot: .reason
        ),
        PluginRoleDefinition(
            id: AgentSlot.orchestrate.rawValue,
            displayName: "Orchestrate",
            pluginID: "merlin",
            scope: "core",
            fallbackSlot: .reason
        ),
        PluginRoleDefinition(
            id: AgentSlot.vision.rawValue,
            displayName: "Vision",
            pluginID: "merlin",
            scope: "core",
            fallbackSlot: .vision
        ),
    ]

    private static func sortRank(for roleID: String) -> Int {
        switch roleID {
        case AgentSlot.execute.rawValue:
            return 0
        case AgentSlot.reason.rawValue:
            return 1
        case AgentSlot.orchestrate.rawValue:
            return 2
        case AgentSlot.vision.rawValue:
            return 3
        default:
            return 10
        }
    }
}
