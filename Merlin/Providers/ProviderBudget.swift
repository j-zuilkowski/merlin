import Foundation

struct ProviderBudget: Sendable, Equatable, Codable {
    let maxInputTokens: Int
    let reservedOutputTokens: Int

    var usableInputTokens: Int { maxInputTokens - reservedOutputTokens }

    static let conservative = ProviderBudget(maxInputTokens: 32_000, reservedOutputTokens: 4_096)

    /// `self` when it has a positive usable input budget; otherwise the
    /// `.conservative` default. A degenerate budget — `usableInputTokens <= 0`,
    /// e.g. a config persisted with `maxInputTokens <= reservedOutputTokens` —
    /// would make every preflight check overflow and kill the run on its first
    /// request (observed as `preflight overflow (5642 > 0)`).
    var preflightSafe: ProviderBudget {
        usableInputTokens > 0 ? self : .conservative
    }
}
