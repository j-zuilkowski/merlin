import Foundation

// MARK: - DomainTaskType

/// A domain-registered task classification. Not a hardcoded enum - domains
/// contribute their own task types at registration time.
struct DomainTaskType: Hashable, Codable, Sendable {
    var domainID: String
    var name: String
    var displayName: String
}

// MARK: - DomainPlugin

/// Adopted by built-in domains (SoftwareDomain) and by MCPDomainAdapter
/// when wrapping an external MCP domain server.
protocol DomainPlugin: Sendable {
    var id: String { get }
    var displayName: String { get }
    var taskTypes: [DomainTaskType] { get }
    var verificationBackend: any VerificationBackend { get }
    var highStakesKeywords: [String] { get }
    /// Appended to the provider's system prompt addendum (if any). nil = nothing added.
    var systemPromptAddendum: String? { get }
    /// MCP tool names contributed by this domain (used by ToolRegistry at domain activation).
    var mcpToolNames: [String] { get }
}

// MARK: - DomainManifest (MCP wire format)

/// JSON shape served at `merlin://domain/manifest` by an MCP domain server.
struct DomainManifest: Decodable, Sendable {
    var id: String
    var displayName: String
    var taskTypes: [DomainTaskType]
    var highStakesKeywords: [String]
    var systemPromptAddendum: String?
    /// Key = task type name, value = list of verification commands for that type.
    var verificationCommands: [String: [ManifestVerificationCommand]]

    struct ManifestVerificationCommand: Decodable, Sendable {
        var label: String
        var command: String
        var passCondition: ManifestPassCondition

        enum ManifestPassCondition: Decodable, Sendable {
            case exitCode(Int)
            case outputContains(String)

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type_ = try container.decode(String.self, forKey: .type)
                switch type_ {
                case "exitCode":
                    self = .exitCode(try container.decode(Int.self, forKey: .value))
                case "outputContains":
                    self = .outputContains(try container.decode(String.self, forKey: .value))
                default:
                    self = .exitCode(0)
                }
            }

            enum CodingKeys: String, CodingKey { case type, value }
        }
    }
}

// MARK: - MCPDomainAdapter

/// Bridges an external MCP domain server (which cannot adopt Swift protocols)
/// into the DomainPlugin protocol by reading its DomainManifest resource.
struct MCPDomainAdapter: DomainPlugin {
    let id: String
    let displayName: String
    let taskTypes: [DomainTaskType]
    let highStakesKeywords: [String]
    let systemPromptAddendum: String?
    let mcpToolNames: [String]
    let verificationBackend: any VerificationBackend
    let mcpServerID: String

    init(manifest: DomainManifest, mcpServerID: String) {
        self.id = manifest.id
        self.displayName = manifest.displayName
        self.taskTypes = manifest.taskTypes
        self.highStakesKeywords = manifest.highStakesKeywords
        self.systemPromptAddendum = manifest.systemPromptAddendum
        self.mcpToolNames = []
        self.verificationBackend = ManifestVerificationBackend(commands: manifest.verificationCommands)
        self.mcpServerID = mcpServerID
    }
}

// MARK: - ManifestVerificationBackend

/// VerificationBackend built from a DomainManifest's verificationCommands map.
struct ManifestVerificationBackend: VerificationBackend {
    private let commandMap: [String: [DomainManifest.ManifestVerificationCommand]]

    init(commands: [String: [DomainManifest.ManifestVerificationCommand]]) {
        self.commandMap = commands
    }

    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]? {
        guard let cmds = commandMap[taskType.name], !cmds.isEmpty else { return nil }
        return cmds.map { c in
            let condition: PassCondition
            switch c.passCondition {
            case .exitCode(let code):
                condition = .exitCode(code)
            case .outputContains(let string):
                condition = .outputContains(string)
            }
            return VerificationCommand(label: c.label, command: c.command, passCondition: condition)
        }
    }
}
