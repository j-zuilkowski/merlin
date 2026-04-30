import Foundation
import NaturalLanguage

// MARK: - EmbeddingProviderProtocol

/// Produces a fixed-length floating-point embedding vector for a text string.
///
/// The `dimension` property declares the output size of every vector returned by
/// `embed(_:)`, which lets callers validate storage and similarity calculations.
protocol EmbeddingProviderProtocol: Sendable {
    /// Number of dimensions in the embedding vector returned by `embed(_:)`.
    var dimension: Int { get }

    /// Produce an embedding for `text`.
    func embed(_ text: String) async throws -> [Float]
}

// MARK: - EmbeddingError

enum EmbeddingError: Error, Sendable {
    /// The contextual embedding model is unavailable on this device.
    case modelUnavailable
    /// The input text produced no tokens.
    case emptyInput
}

// MARK: - NLContextualEmbeddingProvider

/// Production embedding provider backed by `NLContextualEmbedding`.
///
/// The provider downloads Apple’s contextual embedding assets on demand and
/// mean-pools the token vectors into a single sentence embedding.
struct NLContextualEmbeddingProvider: EmbeddingProviderProtocol {
    /// 512 dimensions for the standard English contextual embedding model.
    let dimension: Int = 512

    func embed(_ text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EmbeddingError.emptyInput
        }

        guard let model = NLContextualEmbedding(language: .english) else {
            throw EmbeddingError.modelUnavailable
        }

        if !model.hasAvailableAssets {
            let assetsResult = try await model.requestAssets()
            guard assetsResult == .available else {
                throw EmbeddingError.modelUnavailable
            }
        }

        try model.load()

        let result = try model.embeddingResult(for: trimmed, language: .english)
        var accumulator = [Double](repeating: 0, count: dimension)
        var tokenCount = 0

        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            let count = min(vector.count, self.dimension)
            for index in 0..<count {
                accumulator[index] += vector[index]
            }
            tokenCount += 1
            return true
        }

        guard tokenCount > 0 else {
            throw EmbeddingError.emptyInput
        }

        let scale = 1.0 / Double(tokenCount)
        return accumulator.map { Float($0 * scale) }
    }
}
