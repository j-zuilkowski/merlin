import Foundation

extension ProviderRegistry {
    private static let knownReasoningModels: Set<String> = [
        "claude-3-opus-20240229",
        "claude-3-7-sonnet-20250219",
        "claude-opus-4",
        "claude-sonnet-4"
    ]

    private static let reasoningPatterns: [String] = [
        "qwq",
        "deepseek-r1",
        "r1-"
    ]

    static func reasoningEffortSupported(
        for modelID: String,
        overrides: [String: Bool] = [:]
    ) -> Bool {
        if let override = overrides[modelID] {
            return override
        }
        if knownReasoningModels.contains(modelID) {
            return true
        }
        let lower = modelID.lowercased()
        return reasoningPatterns.contains { lower.contains($0) }
    }
}
