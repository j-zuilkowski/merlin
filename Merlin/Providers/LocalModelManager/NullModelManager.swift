import Foundation

/// No-op manager used when a provider ID is unknown or its base URL cannot be
/// normalized into a concrete local manager. Reports `canReloadAtRuntime = false`
/// and generates explanation-only `RestartInstructions`.
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
