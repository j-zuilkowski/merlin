import Foundation

struct Tier2PluginManifest: Codable, Sendable, Equatable {
    var id: String
    var displayName: String
    var version: String
    var trustTier: RuntimePluginTrustTier
    var enabled: Bool
    var domainIDs: [String]
    var settingsSchema: WorkspaceSettingsSchema?
    var capabilities: [WorkspaceCapability]
    var toolRoutes: [Tier2PluginToolRoute]

    init(
        id: String,
        displayName: String,
        version: String,
        trustTier: RuntimePluginTrustTier,
        enabled: Bool = true,
        domainIDs: [String] = [],
        settingsSchema: WorkspaceSettingsSchema? = nil,
        capabilities: [WorkspaceCapability] = [],
        toolRoutes: [Tier2PluginToolRoute] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.trustTier = trustTier
        self.enabled = enabled
        self.domainIDs = domainIDs
        self.settingsSchema = settingsSchema
        self.capabilities = capabilities
        self.toolRoutes = toolRoutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKeys: [.id])
        displayName = try container.decode(String.self, forKeys: [.displayName, .displayNameSnake])
        version = try container.decode(String.self, forKeys: [.version])
        trustTier = try container.decode(RuntimePluginTrustTier.self, forKeys: [.trustTier, .trustTierSnake])
        enabled = try container.decodeIfPresent(Bool.self, forKeys: [.enabled]) ?? true
        domainIDs = try container.decodeIfPresent([String].self, forKeys: [.domainIDs, .domainIDsSnake]) ?? []
        settingsSchema = try container.decodeIfPresent(WorkspaceSettingsSchema.self, forKeys: [.settingsSchema, .settingsSchemaSnake])
        capabilities = try container.decodeIfPresent([WorkspaceCapability].self, forKeys: [.capabilities]) ?? []
        toolRoutes = try container.decodeIfPresent([Tier2PluginToolRoute].self, forKeys: [.toolRoutes, .toolRoutesSnake]) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(version, forKey: .version)
        try container.encode(trustTier, forKey: .trustTier)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(domainIDs, forKey: .domainIDs)
        try container.encodeIfPresent(settingsSchema, forKey: .settingsSchema)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(toolRoutes, forKey: .toolRoutes)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case displayNameSnake = "display_name"
        case version
        case trustTier
        case trustTierSnake = "trust_tier"
        case enabled
        case domainIDs = "domainIds"
        case domainIDsSnake = "domain_ids"
        case settingsSchema
        case settingsSchemaSnake = "settings_schema"
        case capabilities
        case toolRoutes
        case toolRoutesSnake = "tool_routes"
    }
}

struct Tier2PluginToolRoute: Codable, Sendable, Equatable {
    var toolName: String
    var stableAlias: String?
    var address: WorkspaceMessageAddress
    var requiredPermissionScope: WorkspacePermissionScope

    init(
        toolName: String,
        stableAlias: String? = nil,
        address: WorkspaceMessageAddress,
        requiredPermissionScope: WorkspacePermissionScope
    ) {
        self.toolName = toolName
        self.stableAlias = stableAlias
        self.address = address
        self.requiredPermissionScope = requiredPermissionScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolName = try container.decode(String.self, forKeys: [.toolName, .toolNameSnake])
        stableAlias = try container.decodeIfPresent(String.self, forKeys: [.stableAlias, .stableAliasSnake])
        address = try container.decode(WorkspaceMessageAddress.self, forKeys: [.address])
        requiredPermissionScope = try container.decode(WorkspacePermissionScope.self, forKeys: [
            .requiredPermissionScope,
            .requiredPermissionScopeSnake,
        ])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolName, forKey: .toolName)
        try container.encodeIfPresent(stableAlias, forKey: .stableAlias)
        try container.encode(address, forKey: .address)
        try container.encode(requiredPermissionScope, forKey: .requiredPermissionScope)
    }

    enum CodingKeys: String, CodingKey {
        case toolName
        case toolNameSnake = "tool_name"
        case stableAlias
        case stableAliasSnake = "stable_alias"
        case address
        case requiredPermissionScope
        case requiredPermissionScopeSnake = "required_permission_scope"
    }
}

struct MCPPluginMetadataRegistration: Sendable, Equatable {
    var settingsNamespaces: Set<String>
    var capabilityAddresses: Set<WorkspaceMessageAddress>
}

private extension KeyedDecodingContainer {
    func decode<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) throws -> T {
        for key in keys where contains(key) {
            return try decode(type, forKey: key)
        }
        throw DecodingError.keyNotFound(
            keys[0],
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing any of keys \(keys.map(\.stringValue).joined(separator: ", "))")
        )
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) throws -> T? {
        for key in keys where contains(key) {
            return try decodeIfPresent(type, forKey: key)
        }
        return nil
    }
}
