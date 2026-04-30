import Foundation

/// No-op manager for providers that don't have a specific LocalModelManager implementation.
/// Reports canReloadAtRuntime = false and generates an explanation-only RestartInstructions.
struct NullModelManager: LocalModelManagerProtocol {
    let providerID: String

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: []
    )

    func loadedModels() async throws -> [LoadedModelInfo] { [] }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        throw ModelManagerError.providerUnavailable
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(
            shellCommand: "",
            configSnippet: nil,
            explanation: "No model manager is available for provider '\(providerID)'. Adjust load-time parameters in your provider's settings UI."
        )
    }
}
