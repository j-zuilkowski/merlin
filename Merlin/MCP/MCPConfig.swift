import Foundation

struct MCPServerConfig: Codable, Sendable {
    var command: String
    var args: [String]
    var env: [String: String]

    init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.env = env
    }

    enum CodingKeys: String, CodingKey {
        case command, args, env
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
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
        return MCPConfig(mcpServers: merged)
    }
}
