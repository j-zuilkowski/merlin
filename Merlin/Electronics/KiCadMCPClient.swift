import Foundation

@MainActor
protocol KiCadMCPClient {
    func execute(toolName: String, arguments: [String: Any]) async throws -> String
}

@MainActor
final class KiCadMCPBridgeClient: KiCadMCPClient {
    private let bridge: MCPBridge
    private let serverName: String

    init(serverName: String, bridge: MCPBridge = MCPBridge()) {
        self.serverName = serverName
        self.bridge = bridge
    }

    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        let data = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw KiCadMCPClientError.invalidArguments
        }
        return try await bridge.call(server: serverName, tool: toolName, argumentsJSON: json)
    }
}

enum KiCadMCPClientError: Error {
    case invalidArguments
}
