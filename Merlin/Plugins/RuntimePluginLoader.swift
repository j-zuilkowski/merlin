import Foundation
import Darwin

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
    var builtInFactory: String?
    var dynamicLibraryPath: String?
    var bootstrapSymbol: String?
    var handlerSymbol: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case version
        case trustTier
        case enabled
        case domainIDs = "domainIds"
        case capabilities
        case settingsSchema
        case builtInFactory
        case dynamicLibraryPath
        case bootstrapSymbol
        case handlerSymbol
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
                if plugin.builtInFactory == "electronics" || plugin.id == "electronics" {
                    try await ElectronicsRuntimePlugin().register(into: runtime)
                    continue
                }

                guard let dynamicPlugin = try DynamicRuntimePlugin(metadata: plugin) else {
                    await runtime.bus.publish(healthEvent(plugin: plugin, status: "entrypoint-missing"))
                    continue
                }
                _ = dynamicPlugin.bootstrap()
                if let schema = plugin.settingsSchema {
                    await runtime.bus.registerSettingsSchema(schema)
                }
                for capability in plugin.capabilities {
                    await runtime.bus.registerCapability(capability)
                    await runtime.bus.register(
                        DynamicRuntimePluginHandler(plugin: dynamicPlugin, requiredScope: capability.requiredPermissionScope),
                        for: capability.address
                    )
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

private final class DynamicRuntimePlugin: @unchecked Sendable {
    typealias BootstrapFunction = @convention(c) () -> UnsafePointer<CChar>?
    typealias HandlerFunction = @convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?

    let metadata: RuntimePluginMetadata
    private let handle: UnsafeMutableRawPointer
    private let bootstrapFunction: BootstrapFunction?
    private let handlerFunction: HandlerFunction

    init?(metadata: RuntimePluginMetadata) throws {
        guard let libraryPath = metadata.dynamicLibraryPath,
              let handlerSymbol = metadata.handlerSymbol else {
            return nil
        }

        guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            throw RuntimePluginLoaderError.dynamicLoadFailed(String(cString: dlerror()))
        }
        guard let handlerPointer = dlsym(handle, handlerSymbol) else {
            dlclose(handle)
            throw RuntimePluginLoaderError.dynamicLoadFailed("Missing handler symbol \(handlerSymbol)")
        }

        self.metadata = metadata
        self.handle = handle
        self.handlerFunction = unsafeBitCast(handlerPointer, to: HandlerFunction.self)
        if let bootstrapSymbol = metadata.bootstrapSymbol,
           let bootstrapPointer = dlsym(handle, bootstrapSymbol) {
            self.bootstrapFunction = unsafeBitCast(bootstrapPointer, to: BootstrapFunction.self)
        } else {
            self.bootstrapFunction = nil
        }
    }

    deinit {
        dlclose(handle)
    }

    func bootstrap() -> String? {
        guard let pointer = bootstrapFunction?() else { return nil }
        return String(cString: pointer)
    }

    func dispatch(requestJSON: String) -> String {
        requestJSON.withCString { pointer in
            guard let response = handlerFunction(pointer) else {
                return #"{"status":"failed","message":"plugin handler returned null"}"#
            }
            return String(cString: response)
        }
    }
}

private struct DynamicRuntimePluginHandler: WorkspaceMessageHandler {
    var plugin: DynamicRuntimePlugin
    var requiredScope: WorkspacePermissionScope

    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse {
        guard request.origin.permissionScope.allows(requiredScope) else {
            return .unauthorized(requestID: request.id, message: "plugin capability requires \(requiredScope.rawValue)")
        }
        let envelope = String(data: (try? WorkspaceJSON.encoder.encode(request)) ?? Data(), encoding: .utf8) ?? "{}"
        return .ok(requestID: request.id, payload: .jsonString(plugin.dispatch(requestJSON: envelope)))
    }
}

enum RuntimePluginLoaderError: Error, Equatable {
    case dynamicLoadFailed(String)
}
