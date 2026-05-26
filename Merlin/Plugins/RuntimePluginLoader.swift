import Foundation

enum RuntimePluginTrustTier: String, Codable, Sendable, Equatable {
    case tier1
    case tier2
}

struct RuntimePluginMetadata: Codable, Sendable, Equatable {
    var id: String
    var displayName: String
    var version: String
    var trustTier: RuntimePluginTrustTier
    var enabled: Bool
    var domainIDs: [String]
    var capabilities: [WorkspaceCapability]
    var settingsSchema: WorkspaceSettingsSchema?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case version
        case trustTier
        case enabled
        case domainIDs = "domainIds"
        case capabilities
        case settingsSchema
    }
}

struct RuntimePluginLoader {
    var pluginRoots: [URL]

    func discover() throws -> [RuntimePluginMetadata] {
        let decoder = WorkspaceJSON.decoder
        var plugins: [RuntimePluginMetadata] = []
        for root in pluginRoots {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for directory in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let manifestURL = directory.appendingPathComponent("plugin.json")
                guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
                let data = try Data(contentsOf: manifestURL)
                plugins.append(try decoder.decode(RuntimePluginMetadata.self, from: data))
            }
        }
        return plugins.sorted { $0.id < $1.id }
    }

    @MainActor
    func load(into runtime: WorkspaceRuntime) async throws {
        for plugin in try discover() {
            guard plugin.enabled else { continue }
            switch plugin.trustTier {
            case .tier1:
                for capability in plugin.capabilities {
                    await runtime.bus.registerCapability(capability)
                    await runtime.bus.register(
                        ClosureWorkspaceMessageHandler(requiredScope: capability.requiredPermissionScope) { _ in
                            #"{"status":"ok"}"#
                        },
                        for: capability.address
                    )
                }
                if let schema = plugin.settingsSchema {
                    await runtime.bus.registerSettingsSchema(schema)
                }
                await runtime.bus.publish(healthEvent(plugin: plugin, status: "loaded"))
            case .tier2:
                await runtime.bus.publish(healthEvent(plugin: plugin, status: "transport-only"))
            }
        }
    }

    private func healthEvent(plugin: RuntimePluginMetadata, status: String) -> WorkspaceMessageEvent {
        WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.\(plugin.id)", capability: "health"),
            origin: nil,
            kind: .healthChanged,
            payload: .jsonString(#"{"status":"\#(status)"}"#)
        )
    }
}
