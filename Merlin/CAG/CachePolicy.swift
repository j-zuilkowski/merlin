import Foundation

enum CAGCachePolicy: String, Codable, Sendable, Equatable {
    case disabled
    case ephemeral

    var isCacheable: Bool { self != .disabled }
}

enum CAGToolOrdering {
    static func stable(_ tools: [ToolDefinition]) -> [ToolDefinition] {
        var firstByName: [String: ToolDefinition] = [:]
        for tool in tools where firstByName[tool.function.name] == nil {
            firstByName[tool.function.name] = tool
        }

        return firstByName.keys.sorted().compactMap { firstByName[$0] }
    }
}
