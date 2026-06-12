@preconcurrency import Foundation

struct MCPServerConfig: Codable, Sendable {
    var command: String
    var args: [String]
    var env: [String: String]
    var transportKind: MCPTransportKind
    var transportURL: String?

    init(command: String,
         args: [String] = [],
         env: [String: String] = [:],
         transportKind: MCPTransportKind = .stdio,
         transportURL: String? = nil) {
        self.command = command
        self.args = args
        self.env = env
        self.transportKind = transportKind
        self.transportURL = transportURL
    }

    enum CodingKeys: String, CodingKey {
        case command, args, env
        case transportKind = "transport"
        case transportURL = "url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        transportKind = try container.decodeIfPresent(MCPTransportKind.self, forKey: .transportKind) ?? .stdio
        transportURL = try container.decodeIfPresent(String.self, forKey: .transportURL)
    }

    static func expandEnv(_ env: inout [String: String], from processEnv: [String: String]) {
        for key in Array(env.keys) {
            guard let value = env[key], value.hasPrefix("${"), value.hasSuffix("}") else { continue }
            let varName = String(value.dropFirst(2).dropLast())
            if let resolved = processEnv[varName] {
                env[key] = resolved
            }
        }
    }

    func resolvingProjectRoot(_ projectPath: String) -> MCPServerConfig {
        let replacement = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        return MCPServerConfig(
            command: Self.replaceProjectRootPlaceholder(in: command, with: replacement),
            args: args.map { Self.replaceProjectRootPlaceholder(in: $0, with: replacement) },
            env: env.mapValues { Self.replaceProjectRootPlaceholder(in: $0, with: replacement) },
            transportKind: transportKind,
            transportURL: transportURL.map { Self.replaceProjectRootPlaceholder(in: $0, with: replacement) }
        )
    }

    private static func replaceProjectRootPlaceholder(in value: String, with projectPath: String) -> String {
        value.replacingOccurrences(of: "${MERLIN_PROJECT_ROOT}", with: projectPath)
    }
}

struct MCPConfig: Codable, Sendable {
    var mcpServers: [String: MCPServerConfig]

    enum CodingKeys: String, CodingKey { case mcpServers }

    static func load(from path: String) throws -> MCPConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            return MCPConfig(mcpServers: [:])
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(MCPConfig.self, from: data)
    }

    static func merged(projectPath: String) -> MCPConfig {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let global = (try? load(from: "\(home)/.merlin/mcp.json")) ?? MCPConfig(mcpServers: [:])
        let project = (try? load(from: "\(projectPath)/.mcp.json")) ?? MCPConfig(mcpServers: [:])
        var merged = global.mcpServers
        for (name, config) in project.mcpServers {
            merged[name] = config
        }
        return MCPConfig(mcpServers: merged.mapValues { $0.resolvingProjectRoot(projectPath) })
    }
}
