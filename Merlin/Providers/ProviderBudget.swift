import Foundation

struct ProviderBudget: Sendable, Equatable, Codable {
    let maxInputTokens: Int
    let reservedOutputTokens: Int

    var usableInputTokens: Int { maxInputTokens - reservedOutputTokens }

    static let conservative = ProviderBudget(maxInputTokens: 32_000, reservedOutputTokens: 4_096)
}
