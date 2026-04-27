import Foundation

enum AgentRole: String, Codable, Sendable, CaseIterable {
    case explorer
    case worker
    case `default`
}

struct AgentDefinition: Codable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var description: String
    var instructions: String
    var model: String?
    var role: AgentRole
    var allowedTools: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case instructions
        case model
        case role
        case allowedTools = "allowed_tools"
    }
}

extension AgentDefinition {
    static let explorerToolSet: [String] = [
        "read_file",
        "list_directory",
        "search_files",
        "grep",
        "bash",
        "web_search",
        "rag_search"
    ]

    static let builtinDefault = AgentDefinition(
        name: "default",
        description: "General purpose agent with full tool access.",
        instructions: "",
        model: nil,
        role: .default,
        allowedTools: nil
    )

    static let builtinWorker = AgentDefinition(
        name: "worker",
        description: "Write-capable agent with its own git worktree.",
        instructions: "",
        model: nil,
        role: .worker,
        allowedTools: nil
    )

    static let builtinExplorer = AgentDefinition(
        name: "explorer",
        description: "Read-only research agent. Fast and cheap - use a small model.",
        instructions: "You are a read-only research assistant. Explore the codebase and summarise your findings. Do not modify any files.",
        model: nil,
        role: .explorer,
        allowedTools: explorerToolSet
    )
}
